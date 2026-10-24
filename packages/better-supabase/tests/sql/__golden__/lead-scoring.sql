-- ==== alone: schema supabase/schemas/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block lead-scoring@1 managed
-- @bsb-hash sha256:862ace464d21cfea80d887449b4dbdb0b401fc8e1a9a86bb75535285c476e6d9
-- Scores people, and optionally companies, under a tenant-editable score model. Each record's columns, enrichment status, segments and mail opens, clicks and replies feed the model, and the record is scored again when any of them change.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."lead_score_checks";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."lead_score_checks" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  -- Set when the record, its segments or its mail changed since the last score.
  "stale" boolean not null default true,
  "checked_at" timestamptz,
  constraint "lead_score_checks_pkey" primary key ("subject_type", "subject_id")
);
create index if not exists "lead_score_checks_tenant_idx" on "better_supabase"."lead_score_checks" ("tenant_id");
create index if not exists "lead_score_checks_due_idx" on "better_supabase"."lead_score_checks" ("checked_at" nulls first) where "stale";

alter table "better_supabase"."lead_score_checks" enable row level security;
revoke all on "better_supabase"."lead_score_checks" from anon, authenticated;
grant select on "better_supabase"."lead_score_checks" to authenticated;
grant all on "better_supabase"."lead_score_checks" to service_role;
drop policy if exists "lead_score_checks_read" on "better_supabase"."lead_score_checks";
create policy "lead_score_checks_read" on "better_supabase"."lead_score_checks" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')));

-- The values a lead model's rules and metrics read for one record: its
-- columns by database name, segments (the ids of the segments it is in),
-- mail { sent, opened, clicked, replied, lastSentAt, lastRepliedAt } and
-- enrichment { status, provider, fetchedAt }. Null when there is no such
-- record in the organization.
create or replace function "better_supabase"."lead_fields"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_row jsonb;
  v_tenant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (lead_fields.tenant is not null and coalesce(better_supabase.can('tenant', lead_fields.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  begin
    v_id := lead_fields.subject_id::uuid;
  exception when invalid_text_representation then
    return null;
  end;
  if lead_fields.subject_type = 'person' then
    select to_jsonb(x), x."tenant_id" into v_row, v_tenant from "better_supabase"."people" x where x."id" = v_id;
    if v_row is null or v_tenant is distinct from lead_fields.tenant then
      return null;
    end if;
    return v_row || jsonb_build_object(
      'segments', '[]'::jsonb,
      'mail', '{}'::jsonb,
      'enrichment', null
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_fields"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."lead_fields"(uuid, text, text) to authenticated, service_role;

-- Scores one record under its subject type's lead model and marks it fresh.
create or replace function "better_supabase"."score_lead"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb;
  v_result jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (score_lead.tenant is not null and coalesce(better_supabase.can('tenant', score_lead.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  if score_lead.subject_type not in ('person') then
    raise exception 'lead scoring doesn''t score this subject type' using errcode = '22023', hint = 'LEAD_SCORING_SUBJECT';
  end if;
  v_fields := "better_supabase"."lead_fields"(score_lead.tenant, score_lead.subject_type, score_lead.subject_id);
  if v_fields is null then
    raise exception 'no such record' using errcode = 'P0002', hint = 'LEAD_SCORING_NOT_FOUND';
  end if;
  v_result := "better_supabase"."compute_score"(score_lead.tenant, 'lead', score_lead.subject_type, score_lead.subject_id, v_fields);
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id", "stale", "checked_at")
  values (score_lead.tenant, score_lead.subject_type, score_lead.subject_id, false, now())
  on conflict on constraint "lead_score_checks_pkey" do update
    set "stale" = false, "checked_at" = now();
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."score_lead"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."score_lead"(uuid, text, text) to authenticated, service_role;

-- Scores up to max_count records that changed or weren't scored for
-- rescoreAfterHours, whose organization has an enabled lead model. Records
-- that were removed lose their check row. Returns how many it scored.
create or replace function "better_supabase"."score_leads_due"(max_count integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_check "better_supabase"."lead_score_checks";
  v_count integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  select x."tenant_id", 'person', x."id"::text
  from "better_supabase"."people" x
  where x."archived_at" is null
    and not exists (select 1 from "better_supabase"."lead_score_checks" k where k."subject_type" = 'person' and k."subject_id" = x."id"::text)
  limit least(greatest(coalesce(max_count, 100), 1), 1000)
  on conflict do nothing;
  for v_check in
    select k.* from "better_supabase"."lead_score_checks" k
    where (k."stale" or k."checked_at" < now() - interval '24 hours')
      and exists (
        select 1 from "better_supabase"."score_models" m
        where m."tenant_id" = k."tenant_id" and m."key" = 'lead'
          and m."subject_type" = k."subject_type" and m."enabled"
      )
    order by k."checked_at" nulls first
    limit least(greatest(coalesce(max_count, 100), 1), 1000)
    for update of k skip locked
  loop
    if "better_supabase"."lead_fields"(v_check."tenant_id", v_check."subject_type", v_check."subject_id") is null then
      delete from "better_supabase"."lead_score_checks" k where k."subject_type" = v_check."subject_type" and k."subject_id" = v_check."subject_id";
      continue;
    end if;
    perform "better_supabase"."score_lead"(v_check."tenant_id", v_check."subject_type", v_check."subject_id");
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."score_leads_due"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."score_leads_due"(integer) to service_role;


create or replace function "better_supabase"."lead_person_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  values (new."tenant_id", 'person', new."id"::text)
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_person_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_person_changed" on "better_supabase"."people";
create trigger "bsb_person_changed"
  after insert or update on "better_supabase"."people"
  for each row execute function "better_supabase"."lead_person_changed"();

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."lead_score_checks";
create policy bsb_tenant_scope on "better_supabase"."lead_score_checks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block-data lead-scoring
-- @bsb-hash sha256:203a68f20ea218ac8f9ece257a8d1077295048204e38b54f97d5f2b29b7e24d8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('lead-scoring', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block lead-scoring@1 managed
-- @bsb-hash sha256:7fcbc1b5ae5735381668ef5e4e6bc18f3bce54098c027da211e06d62534799ab
-- Scores people, and optionally companies, under a tenant-editable score model. Each record's columns, enrichment status, segments and mail opens, clicks and replies feed the model, and the record is scored again when any of them change.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."lead_score_checks";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."lead_score_checks" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  -- Set when the record, its segments or its mail changed since the last score.
  "stale" boolean not null default true,
  "checked_at" timestamptz,
  constraint "lead_score_checks_pkey" primary key ("subject_type", "subject_id")
);
create index if not exists "lead_score_checks_tenant_idx" on "better_supabase"."lead_score_checks" ("tenant_id");
create index if not exists "lead_score_checks_due_idx" on "better_supabase"."lead_score_checks" ("checked_at" nulls first) where "stale";

alter table "better_supabase"."lead_score_checks" enable row level security;
revoke all on "better_supabase"."lead_score_checks" from anon, authenticated;
grant select on "better_supabase"."lead_score_checks" to authenticated;
grant all on "better_supabase"."lead_score_checks" to service_role;
drop policy if exists "lead_score_checks_read" on "better_supabase"."lead_score_checks";
create policy "lead_score_checks_read" on "better_supabase"."lead_score_checks" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')));

-- The values a lead model's rules and metrics read for one record: its
-- columns by database name, segments (the ids of the segments it is in),
-- mail { sent, opened, clicked, replied, lastSentAt, lastRepliedAt } and
-- enrichment { status, provider, fetchedAt }. Null when there is no such
-- record in the organization.
create or replace function "better_supabase"."lead_fields"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_row jsonb;
  v_tenant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (lead_fields.tenant is not null and coalesce(better_supabase.can('tenant', lead_fields.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  begin
    v_id := lead_fields.subject_id::uuid;
  exception when invalid_text_representation then
    return null;
  end;
  if lead_fields.subject_type = 'person' then
    select to_jsonb(x), x."tenant_id" into v_row, v_tenant from "better_supabase"."people" x where x."id" = v_id;
    if v_row is null or v_tenant is distinct from lead_fields.tenant then
      return null;
    end if;
    return v_row || jsonb_build_object(
      'segments', (select coalesce(jsonb_agg(x."segment_id"::text order by x."segment_id"), '[]'::jsonb)
    from "better_supabase"."segment_members" x
    join "better_supabase"."segments" g on g."id" = x."segment_id"
    where g."subject_type" = lead_fields.subject_type and x."subject_id" = lead_fields.subject_id),
      'mail', (select jsonb_build_object(
      'sent', count(*) filter (where y."direction" = 'outbound'),
      'opened', count(*) filter (where y."direction" = 'outbound' and y."opened_at" is not null),
      'clicked', count(*) filter (where y."direction" = 'outbound' and y."clicked_at" is not null),
      'replied', count(*) filter (where y."direction" = 'inbound'),
      'lastSentAt', max(y."sent_at") filter (where y."direction" = 'outbound'),
      'lastRepliedAt', max(y."sent_at") filter (where y."direction" = 'inbound')
    )
    from "better_supabase"."mail_thread_subjects" k
    join "better_supabase"."mail_messages" y on y."thread_id" = k."thread_id"
    where k."subject_type" = lead_fields.subject_type and k."subject_id" = lead_fields.subject_id),
      'enrichment', (select jsonb_build_object('status', x."status", 'provider', x."provider", 'fetchedAt', x."fetched_at")
    from "better_supabase"."enrichments" x
    where x."person_id" = v_id
    order by x."fetched_at" desc nulls last
    limit 1)
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_fields"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."lead_fields"(uuid, text, text) to authenticated, service_role;

-- Scores one record under its subject type's lead model and marks it fresh.
create or replace function "better_supabase"."score_lead"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb;
  v_result jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (score_lead.tenant is not null and coalesce(better_supabase.can('tenant', score_lead.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  if score_lead.subject_type not in ('person') then
    raise exception 'lead scoring doesn''t score this subject type' using errcode = '22023', hint = 'LEAD_SCORING_SUBJECT';
  end if;
  v_fields := "better_supabase"."lead_fields"(score_lead.tenant, score_lead.subject_type, score_lead.subject_id);
  if v_fields is null then
    raise exception 'no such record' using errcode = 'P0002', hint = 'LEAD_SCORING_NOT_FOUND';
  end if;
  v_result := "better_supabase"."compute_score"(score_lead.tenant, 'lead', score_lead.subject_type, score_lead.subject_id, v_fields);
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id", "stale", "checked_at")
  values (score_lead.tenant, score_lead.subject_type, score_lead.subject_id, false, now())
  on conflict on constraint "lead_score_checks_pkey" do update
    set "stale" = false, "checked_at" = now();
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."score_lead"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."score_lead"(uuid, text, text) to authenticated, service_role;

-- Scores up to max_count records that changed or weren't scored for
-- rescoreAfterHours, whose organization has an enabled lead model. Records
-- that were removed lose their check row. Returns how many it scored.
create or replace function "better_supabase"."score_leads_due"(max_count integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_check "better_supabase"."lead_score_checks";
  v_count integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  select x."tenant_id", 'person', x."id"::text
  from "better_supabase"."people" x
  where x."archived_at" is null
    and not exists (select 1 from "better_supabase"."lead_score_checks" k where k."subject_type" = 'person' and k."subject_id" = x."id"::text)
  limit least(greatest(coalesce(max_count, 100), 1), 1000)
  on conflict do nothing;
  for v_check in
    select k.* from "better_supabase"."lead_score_checks" k
    where (k."stale" or k."checked_at" < now() - interval '24 hours')
      and exists (
        select 1 from "better_supabase"."score_models" m
        where m."tenant_id" = k."tenant_id" and m."key" = 'lead'
          and m."subject_type" = k."subject_type" and m."enabled"
      )
    order by k."checked_at" nulls first
    limit least(greatest(coalesce(max_count, 100), 1), 1000)
    for update of k skip locked
  loop
    if "better_supabase"."lead_fields"(v_check."tenant_id", v_check."subject_type", v_check."subject_id") is null then
      delete from "better_supabase"."lead_score_checks" k where k."subject_type" = v_check."subject_type" and k."subject_id" = v_check."subject_id";
      continue;
    end if;
    perform "better_supabase"."score_lead"(v_check."tenant_id", v_check."subject_type", v_check."subject_id");
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."score_leads_due"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."score_leads_due"(integer) to service_role;


create or replace function "better_supabase"."lead_person_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  values (new."tenant_id", 'person', new."id"::text)
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_person_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_person_changed" on "better_supabase"."people";
create trigger "bsb_person_changed"
  after insert or update on "better_supabase"."people"
  for each row execute function "better_supabase"."lead_person_changed"();

create or replace function "better_supabase"."lead_segment_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  select old."tenant_id", g."subject_type", old."subject_id"
  from "better_supabase"."segments" g
  where g."id" = old."segment_id" and g."subject_type" in ('person')
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  else
    insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  select new."tenant_id", g."subject_type", new."subject_id"
  from "better_supabase"."segments" g
  where g."id" = new."segment_id" and g."subject_type" in ('person')
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_segment_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_segment_changed" on "better_supabase"."segment_members";
create trigger "bsb_segment_changed"
  after insert or delete on "better_supabase"."segment_members"
  for each row execute function "better_supabase"."lead_segment_changed"();

create or replace function "better_supabase"."lead_mail_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  select k."tenant_id", k."subject_type", k."subject_id"
  from "better_supabase"."mail_thread_subjects" k
  where k."thread_id" = new."thread_id" and k."subject_type" in ('person')
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_mail_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_mail_changed" on "better_supabase"."mail_messages";
create trigger "bsb_mail_changed"
  after insert or update of "opened_at", "clicked_at" on "better_supabase"."mail_messages"
  for each row execute function "better_supabase"."lead_mail_changed"();

create or replace function "better_supabase"."lead_mail_linked"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."subject_type" in ('person') then
    insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  values (new."tenant_id", new."subject_type", new."subject_id")
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_mail_linked"() from public, anon, authenticated;
drop trigger if exists "bsb_mail_linked" on "better_supabase"."mail_thread_subjects";
create trigger "bsb_mail_linked"
  after insert on "better_supabase"."mail_thread_subjects"
  for each row execute function "better_supabase"."lead_mail_linked"();

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."lead_score_checks";
create policy bsb_tenant_scope on "better_supabase"."lead_score_checks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block-data lead-scoring
-- @bsb-hash sha256:203a68f20ea218ac8f9ece257a8d1077295048204e38b54f97d5f2b29b7e24d8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('lead-scoring', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block lead-scoring@1 managed
-- @bsb-hash sha256:10610a54829b9d1e29d3984009ff2a1f4c64927c9d24e894d9e2b46e225a8874
-- Scores people, and optionally companies, under a tenant-editable score model. Each record's columns, enrichment status, segments and mail opens, clicks and replies feed the model, and the record is scored again when any of them change.
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
    drop policy if exists bsb_tenant_scope on "app_private"."lead_score_checks";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create table if not exists "app_private"."lead_score_checks" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  -- Set when the record, its segments or its mail changed since the last score.
  "stale" boolean not null default true,
  "checked_at" timestamptz,
  constraint "lead_score_checks_pkey" primary key ("subject_type", "subject_id")
);
create index if not exists "lead_score_checks_tenant_idx" on "app_private"."lead_score_checks" ("tenant_id");
create index if not exists "lead_score_checks_due_idx" on "app_private"."lead_score_checks" ("checked_at" nulls first) where "stale";

alter table "app_private"."lead_score_checks" enable row level security;
revoke all on "app_private"."lead_score_checks" from anon, authenticated;
grant select on "app_private"."lead_score_checks" to authenticated;
grant all on "app_private"."lead_score_checks" to service_role;
drop policy if exists "lead_score_checks_read" on "app_private"."lead_score_checks";
create policy "lead_score_checks_read" on "app_private"."lead_score_checks" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')));

-- The values a lead model's rules and metrics read for one record: its
-- columns by database name, segments (the ids of the segments it is in),
-- mail { sent, opened, clicked, replied, lastSentAt, lastRepliedAt } and
-- enrichment { status, provider, fetchedAt }. Null when there is no such
-- record in the organization.
create or replace function "app_private"."lead_fields"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_row jsonb;
  v_tenant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (lead_fields.tenant is not null and coalesce(better_supabase.can('tenant', lead_fields.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  begin
    v_id := lead_fields.subject_id::uuid;
  exception when invalid_text_representation then
    return null;
  end;
  if lead_fields.subject_type = 'person' then
    select to_jsonb(x), x."tenant_id" into v_row, v_tenant from "better_supabase"."people" x where x."id" = v_id;
    if v_row is null or v_tenant is distinct from lead_fields.tenant then
      return null;
    end if;
    return v_row || jsonb_build_object(
      'segments', '[]'::jsonb,
      'mail', '{}'::jsonb,
      'enrichment', null
    );
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."lead_fields"(uuid, text, text) from public, anon;
grant execute on function "app_private"."lead_fields"(uuid, text, text) to authenticated, service_role;

-- Scores one record under its subject type's lead model and marks it fresh.
create or replace function "app_private"."score_lead"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb;
  v_result jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (score_lead.tenant is not null and coalesce(better_supabase.can('tenant', score_lead.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  if score_lead.subject_type not in ('person') then
    raise exception 'lead scoring doesn''t score this subject type' using errcode = '22023', hint = 'LEAD_SCORING_SUBJECT';
  end if;
  v_fields := "app_private"."lead_fields"(score_lead.tenant, score_lead.subject_type, score_lead.subject_id);
  if v_fields is null then
    raise exception 'no such record' using errcode = 'P0002', hint = 'LEAD_SCORING_NOT_FOUND';
  end if;
  v_result := "better_supabase"."compute_score"(score_lead.tenant, 'lead', score_lead.subject_type, score_lead.subject_id, v_fields);
  insert into "app_private"."lead_score_checks" ("tenant_id", "subject_type", "subject_id", "stale", "checked_at")
  values (score_lead.tenant, score_lead.subject_type, score_lead.subject_id, false, now())
  on conflict on constraint "lead_score_checks_pkey" do update
    set "stale" = false, "checked_at" = now();
  return v_result;
end;
$$;
revoke execute on function "app_private"."score_lead"(uuid, text, text) from public, anon;
grant execute on function "app_private"."score_lead"(uuid, text, text) to authenticated, service_role;

-- Scores up to max_count records that changed or weren't scored for
-- rescoreAfterHours, whose organization has an enabled lead model. Records
-- that were removed lose their check row. Returns how many it scored.
create or replace function "app_private"."score_leads_due"(max_count integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_check "app_private"."lead_score_checks";
  v_count integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  insert into "app_private"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  select x."tenant_id", 'person', x."id"::text
  from "better_supabase"."people" x
  where x."archived_at" is null
    and not exists (select 1 from "app_private"."lead_score_checks" k where k."subject_type" = 'person' and k."subject_id" = x."id"::text)
  limit least(greatest(coalesce(max_count, 100), 1), 1000)
  on conflict do nothing;
  for v_check in
    select k.* from "app_private"."lead_score_checks" k
    where (k."stale" or k."checked_at" < now() - interval '24 hours')
      and exists (
        select 1 from "better_supabase"."score_models" m
        where m."tenant_id" = k."tenant_id" and m."key" = 'lead'
          and m."subject_type" = k."subject_type" and m."enabled"
      )
    order by k."checked_at" nulls first
    limit least(greatest(coalesce(max_count, 100), 1), 1000)
    for update of k skip locked
  loop
    if "app_private"."lead_fields"(v_check."tenant_id", v_check."subject_type", v_check."subject_id") is null then
      delete from "app_private"."lead_score_checks" k where k."subject_type" = v_check."subject_type" and k."subject_id" = v_check."subject_id";
      continue;
    end if;
    perform "app_private"."score_lead"(v_check."tenant_id", v_check."subject_type", v_check."subject_id");
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."score_leads_due"(integer) from public, anon, authenticated;
grant execute on function "app_private"."score_leads_due"(integer) to service_role;


create or replace function "app_private"."lead_person_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "app_private"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  values (new."tenant_id", 'person', new."id"::text)
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  return null;
end;
$$;
revoke execute on function "app_private"."lead_person_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_person_changed" on "better_supabase"."people";
create trigger "bsb_person_changed"
  after insert or update on "better_supabase"."people"
  for each row execute function "app_private"."lead_person_changed"();

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "app_private"."lead_score_checks";
create policy bsb_tenant_scope on "app_private"."lead_score_checks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block-data lead-scoring
-- @bsb-hash sha256:203a68f20ea218ac8f9ece257a8d1077295048204e38b54f97d5f2b29b7e24d8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('lead-scoring', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block lead-scoring@1 managed
-- @bsb-hash sha256:7db916acc0f478d93188c30b478b658a4e438c19045bceff48d941b967702058
-- Scores people, and optionally companies, under a tenant-editable score model. Each record's columns, enrichment status, segments and mail opens, clicks and replies feed the model, and the record is scored again when any of them change.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."lead_score_checks";
  exception when undefined_table then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."lead_score_checks" (
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  -- Set when the record, its segments or its mail changed since the last score.
  "stale" boolean not null default true,
  "checked_at" timestamptz,
  constraint "lead_score_checks_pkey" primary key ("subject_type", "subject_id")
);
create index if not exists "lead_score_checks_tenant_idx" on "better_supabase"."lead_score_checks" ("tenant_id");
create index if not exists "lead_score_checks_due_idx" on "better_supabase"."lead_score_checks" ("checked_at" nulls first) where "stale";

alter table "better_supabase"."lead_score_checks" enable row level security;
revoke all on "better_supabase"."lead_score_checks" from anon, authenticated;
grant select on "better_supabase"."lead_score_checks" to authenticated;
grant all on "better_supabase"."lead_score_checks" to service_role;
drop policy if exists "lead_score_checks_read" on "better_supabase"."lead_score_checks";
create policy "lead_score_checks_read" on "better_supabase"."lead_score_checks" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')));

-- The values a lead model's rules and metrics read for one record: its
-- columns by database name, segments (the ids of the segments it is in),
-- mail { sent, opened, clicked, replied, lastSentAt, lastRepliedAt } and
-- enrichment { status, provider, fetchedAt }. Null when there is no such
-- record in the organization.
create or replace function "better_supabase"."lead_fields"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_row jsonb;
  v_tenant uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (lead_fields.tenant is not null and coalesce(better_supabase.can('tenant', lead_fields.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  begin
    v_id := lead_fields.subject_id::uuid;
  exception when invalid_text_representation then
    return null;
  end;
  if lead_fields.subject_type = 'person' then
    select to_jsonb(x), x."tenant_id" into v_row, v_tenant from "better_supabase"."people" x where x."id" = v_id;
    if v_row is null or v_tenant is distinct from lead_fields.tenant then
      return null;
    end if;
    return v_row || jsonb_build_object(
      'segments', '[]'::jsonb,
      'mail', '{}'::jsonb,
      'enrichment', null
    );
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_fields"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."lead_fields"(uuid, text, text) to authenticated, service_role;

-- Scores one record under its subject type's lead model and marks it fresh.
create or replace function "better_supabase"."score_lead"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_fields jsonb;
  v_result jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (score_lead.tenant is not null and coalesce(better_supabase.can('tenant', score_lead.tenant, 'scores.compute'), false))) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  if score_lead.subject_type not in ('person') then
    raise exception 'lead scoring doesn''t score this subject type' using errcode = '22023', hint = 'LEAD_SCORING_SUBJECT';
  end if;
  v_fields := "better_supabase"."lead_fields"(score_lead.tenant, score_lead.subject_type, score_lead.subject_id);
  if v_fields is null then
    raise exception 'no such record' using errcode = 'P0002', hint = 'LEAD_SCORING_NOT_FOUND';
  end if;
  v_result := "better_supabase"."compute_score"(score_lead.tenant, 'lead', score_lead.subject_type, score_lead.subject_id, v_fields);
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id", "stale", "checked_at")
  values (score_lead.tenant, score_lead.subject_type, score_lead.subject_id, false, now())
  on conflict on constraint "lead_score_checks_pkey" do update
    set "stale" = false, "checked_at" = now();
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."score_lead"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."score_lead"(uuid, text, text) to authenticated, service_role;

-- Scores up to max_count records that changed or weren't scored for
-- rescoreAfterHours, whose organization has an enabled lead model. Records
-- that were removed lose their check row. Returns how many it scored.
create or replace function "better_supabase"."score_leads_due"(max_count integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_check "better_supabase"."lead_score_checks";
  v_count integer := 0;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'not allowed to score leads' using errcode = '42501', hint = 'LEAD_SCORING_FORBIDDEN';
  end if;
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  select x."tenant_id", 'person', x."id"::text
  from "better_supabase"."people" x
  where x."archived_at" is null
    and not exists (select 1 from "better_supabase"."lead_score_checks" k where k."subject_type" = 'person' and k."subject_id" = x."id"::text)
  limit least(greatest(coalesce(max_count, 100), 1), 1000)
  on conflict do nothing;
  for v_check in
    select k.* from "better_supabase"."lead_score_checks" k
    where (k."stale" or k."checked_at" < now() - interval '24 hours')
      and exists (
        select 1 from "better_supabase"."score_models" m
        where m."tenant_id" = k."tenant_id" and m."key" = 'lead'
          and m."subject_type" = k."subject_type" and m."enabled"
      )
    order by k."checked_at" nulls first
    limit least(greatest(coalesce(max_count, 100), 1), 1000)
    for update of k skip locked
  loop
    if "better_supabase"."lead_fields"(v_check."tenant_id", v_check."subject_type", v_check."subject_id") is null then
      delete from "better_supabase"."lead_score_checks" k where k."subject_type" = v_check."subject_type" and k."subject_id" = v_check."subject_id";
      continue;
    end if;
    perform "better_supabase"."score_lead"(v_check."tenant_id", v_check."subject_type", v_check."subject_id");
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."score_leads_due"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."score_leads_due"(integer) to service_role;


create or replace function "better_supabase"."lead_person_changed"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."lead_score_checks" ("tenant_id", "subject_type", "subject_id")
  values (new."tenant_id", 'person', new."id"::text)
  on conflict ("subject_type", "subject_id") do update set "stale" = true;
  return null;
end;
$$;
revoke execute on function "better_supabase"."lead_person_changed"() from public, anon, authenticated;
drop trigger if exists "bsb_person_changed" on "better_supabase"."people";
create trigger "bsb_person_changed"
  after insert or update on "better_supabase"."people"
  for each row execute function "better_supabase"."lead_person_changed"();

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."lead_score_checks";
create policy bsb_tenant_scope on "better_supabase"."lead_score_checks" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('scores.compute')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.lead-scoring.api: entry points for the Data API.
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

create or replace function "api"."lead_fields"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."lead_fields"($1, $2, $3) $$;
revoke execute on function "api"."lead_fields"(uuid, text, text) from public, anon;
grant execute on function "api"."lead_fields"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."score_lead"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."score_lead"($1, $2, $3) $$;
revoke execute on function "api"."score_lead"(uuid, text, text) from public, anon;
grant execute on function "api"."score_lead"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."score_leads_due"(max_count integer default 100)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."score_leads_due"($1) $$;
revoke execute on function "api"."score_leads_due"(integer) from public, anon, authenticated;
grant execute on function "api"."score_leads_due"(integer) to service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_139_lead_scoring.sql
-- better-supabase module: lead-scoring
-- @bsb-block-data lead-scoring
-- @bsb-hash sha256:203a68f20ea218ac8f9ece257a8d1077295048204e38b54f97d5f2b29b7e24d8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('lead-scoring', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
