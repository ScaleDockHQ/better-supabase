-- better-supabase module: activities
-- @bsb-block activities@1 managed
-- Calls, emails, meetings, notes and tasks logged on one or more registered records, with an owner, a due time and an outcome, a record's timeline, its next step and a member's open tasks.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Calls, emails, meetings, notes and tasks logged on one or more records.
create table if not exists "better_supabase"."engagements" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "type" text not null,
  "title" text not null check (length("title") between 1 and 500),
  "body" text,
  "outcome" text,
  "owner_user_id" uuid,
  "due_at" timestamptz,
  "done_at" timestamptz,
  "duration_seconds" integer check ("duration_seconds" >= 0),
  "external_ref" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists engagements_owner_open_idx on "better_supabase"."engagements" ("tenant_id", "owner_user_id", "due_at") where "done_at" is null;
create index if not exists engagements_tenant_created_idx on "better_supabase"."engagements" ("tenant_id", "created_at" desc);
create unique index if not exists engagements_external_ref_idx on "better_supabase"."engagements" ("tenant_id", "external_ref") where "external_ref" is not null;
alter table "better_supabase"."engagements" enable row level security;
revoke all on "better_supabase"."engagements" from anon, authenticated;
grant select on "better_supabase"."engagements" to authenticated;
grant all on "better_supabase"."engagements" to service_role;
create table if not exists "better_supabase"."engagement_subjects" (
  "tenant_id" uuid not null,
  "engagement_id" uuid not null references "better_supabase"."engagements" ("id") on delete cascade,
  "subject_type" text not null,
  "subject_id" text not null,
  "position" integer not null default 1,
  primary key ("engagement_id", "subject_type", "subject_id")
);
create index if not exists engagement_subjects_subject_idx on "better_supabase"."engagement_subjects" ("subject_type", "subject_id");
alter table "better_supabase"."engagement_subjects" enable row level security;
revoke all on "better_supabase"."engagement_subjects" from anon, authenticated;
grant select on "better_supabase"."engagement_subjects" to authenticated;
grant all on "better_supabase"."engagement_subjects" to service_role;
-- A link is visible when its record is; an engagement when one of its
-- records is, or it has none.
drop policy if exists engagement_subjects_read on "better_supabase"."engagement_subjects";
create policy engagement_subjects_read on "better_supabase"."engagement_subjects" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('engagements.read')) and "better_supabase"."can_subject"("subject_type", "subject_id", 'read'));
drop policy if exists engagements_read on "better_supabase"."engagements";
create policy engagements_read on "better_supabase"."engagements" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('engagements.read')) and (
  not exists (select 1 from "better_supabase"."engagement_subjects" x where x."engagement_id" = "id")
  or exists (select 1 from "better_supabase"."engagement_subjects" x where x."engagement_id" = "id" and "better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'))
));

-- Logs an engagement on the records in subjects ([{ type, id }], the first
-- is its main record). attrs: type, title, body, outcome, ownerId, dueAt,
-- doneAt, durationSeconds, externalRef and fields (the extra columns by
-- name). A known externalRef updates instead.
create or replace function "better_supabase"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_tenant uuid := log_engagement.tenant;
  v_type text := log_engagement.attrs ->> 'type';
  v_title text := nullif(trim(log_engagement.attrs ->> 'title'), '');
  v_owner uuid := coalesce(nullif(log_engagement.attrs ->> 'ownerId', '')::uuid, auth.uid());
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.write'), false)) then
    raise exception 'not allowed to log engagements' using errcode = '42501', hint = 'ENGAGEMENT_FORBIDDEN';
  end if;
  if v_type is null or not (v_type = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  if v_title is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'ENGAGEMENT_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_engagement_log"(uuid, jsonb, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb, $3::jsonb)', v_hook::oid::regproc)
        using log_engagement.tenant, log_engagement.attrs, log_engagement.subjects;
    end if;
  end;
  insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "outcome", "owner_user_id", "due_at", "done_at", "duration_seconds", "external_ref", "created_by")
  values (v_tenant, v_type, v_title, log_engagement.attrs ->> 'body', log_engagement.attrs ->> 'outcome', v_owner,
    (log_engagement.attrs ->> 'dueAt')::timestamptz, (log_engagement.attrs ->> 'doneAt')::timestamptz,
    (log_engagement.attrs ->> 'durationSeconds')::integer, log_engagement.attrs ->> 'externalRef', auth.uid())
  on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
    "title" = excluded."title", "body" = excluded."body", "outcome" = excluded."outcome",
    "due_at" = excluded."due_at", "done_at" = excluded."done_at",
    "duration_seconds" = excluded."duration_seconds", "updated_at" = now()
  returning "id" into v_id;
  
  if jsonb_typeof(coalesce(log_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(log_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_engagement_log"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes the keys attrs names, and the records when subjects isn't null.
-- The author, the owner and members with engagements.manage may edit.
create or replace function "better_supabase"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := update_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_title text;
  v_owner uuid;
  v_previous_owner uuid;
  v_item jsonb;
  v_subjects jsonb;
  v_first jsonb;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type", x."owner_user_id" into v_tenant, v_type, v_previous_owner
  from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if update_engagement.attrs ? 'type' and not (update_engagement.attrs ->> 'type' = any ('{call,email,meeting,note,task}'::text[])) then
    raise exception 'unknown engagement type' using errcode = '22023', hint = 'ENGAGEMENT_TYPE_INVALID';
  end if;
  update "better_supabase"."engagements" x set
    "type" = coalesce(update_engagement.attrs ->> 'type', x."type"),
    "title" = coalesce(nullif(trim(update_engagement.attrs ->> 'title'), ''), x."title"),
    "body" = case when update_engagement.attrs ? 'body' then update_engagement.attrs ->> 'body' else x."body" end,
    "outcome" = case when update_engagement.attrs ? 'outcome' then update_engagement.attrs ->> 'outcome' else x."outcome" end,
    "external_ref" = case when update_engagement.attrs ? 'externalRef' then update_engagement.attrs ->> 'externalRef' else x."external_ref" end,
    "owner_user_id" = case when update_engagement.attrs ? 'ownerId' then nullif(update_engagement.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
    "due_at" = case when update_engagement.attrs ? 'dueAt' then (update_engagement.attrs ->> 'dueAt')::timestamptz else x."due_at" end,
    "done_at" = case when update_engagement.attrs ? 'doneAt' then (update_engagement.attrs ->> 'doneAt')::timestamptz else x."done_at" end,
    "duration_seconds" = case when update_engagement.attrs ? 'durationSeconds' then (update_engagement.attrs ->> 'durationSeconds')::integer else x."duration_seconds" end,
    "updated_at" = now()
  where x."id" = v_id
  returning x."type", x."title", x."owner_user_id" into v_type, v_title, v_owner;
  if update_engagement.subjects is not null then
    
  if jsonb_typeof(coalesce(update_engagement.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'ENGAGEMENT_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'ENGAGEMENT_SUBJECT_FORBIDDEN';
    end if;
  end loop;
  delete from "better_supabase"."engagement_subjects" x where x."engagement_id" = v_id;
  insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
  select v_tenant, v_id, s.value ->> 'type', s.value ->> 'id', s.ordinality::integer
  from jsonb_array_elements(coalesce(update_engagement.subjects, '[]')) with ordinality s
  on conflict do nothing;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
  v_first := v_subjects -> 0;
  else
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
  end if;
  perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  if v_owner is not null and v_owner is distinct from auth.uid() and v_owner is distinct from v_previous_owner then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'engagement.assigned',
      'tenant', v_tenant,
      'actor', auth.uid(),
      'subject_type', v_first ->> 'type',
      'subject_id', v_first ->> 'id',
      'summary', v_title,
      'recipients', jsonb_build_array(v_owner),
      'watchers', false,
      'key', 'engagement.assigned:' || v_id::text || ':' || v_owner::text,
      'data', jsonb_build_object('engagementId', v_id)
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks an engagement done now (done true) or open again.
create or replace function "better_supabase"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := complete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = complete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  update "better_supabase"."engagements" x set
    "done_at" = case when complete_engagement.done then coalesce(x."done_at", now()) end,
    "outcome" = coalesce(complete_engagement.outcome, x."outcome"),
    "updated_at" = now()
  where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if complete_engagement.done then
    perform "better_supabase".emit_event('engagement.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) from "better_supabase"."engagements" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "better_supabase"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "better_supabase"."delete_engagement"(engagement uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_engagement.engagement;
  v_tenant uuid;
  v_type text;
  v_subjects jsonb := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = delete_engagement.engagement), '[]'::jsonb);
  v_first jsonb := v_subjects -> 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."engagements" x where x."id" = v_id and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false))
  returning x."tenant_id", x."type" into v_tenant, v_type;
  if v_tenant is null then
    return false;
  end if;
  perform "better_supabase".emit_event('engagement.deleted', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_engagement"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_engagement"(uuid) to authenticated, service_role;

-- A record's engagements the caller can see, newest first: done ones by
-- when they happened, open ones by when they are due. before continues
-- after the last row of the previous page.
create or replace function "better_supabase"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, coalesce(x."done_at", x."due_at", x."created_at") as at, x."id" as id
    from "better_supabase"."engagements" x
    join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
    where k."subject_type" = engagements_of.subject_type and k."subject_id" = engagements_of.subject_id
      and (engagements_of.types is null or x."type" = any (engagements_of.types))
      and (engagements_of.before is null or coalesce(x."done_at", x."due_at", x."created_at") < engagements_of.before)
    order by at desc, id desc
    limit least(greatest(coalesce(engagements_of.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

-- The next open engagement with a due time on a record, earliest first,
-- for a "next step" and an overdue flag; null when none is planned.
create or replace function "better_supabase"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now())
  from "better_supabase"."engagements" x
  join "better_supabase"."engagement_subjects" k on k."engagement_id" = x."id"
  where k."subject_type" = next_engagement.subject_type and k."subject_id" = next_engagement.subject_id
    and x."done_at" is null and x."due_at" is not null
  order by x."due_at", x."id"
  limit 1
$$;
revoke execute on function "better_supabase"."next_engagement"(text, text) from public, anon;
grant execute on function "better_supabase"."next_engagement"(text, text) to authenticated, service_role;

-- A member's open engagements in a tenant, earliest due first: a task list.
create or replace function "better_supabase"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.due nulls last, p.id), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()) as value, x."due_at" as due, x."id" as id
    from "better_supabase"."engagements" x
    where x."tenant_id" = open_engagements.tenant
      and x."owner_user_id" = coalesce(open_engagements.owner, auth.uid())
      and x."done_at" is null
      and (open_engagements.due_before is null or x."due_at" < open_engagements.due_before)
    order by x."due_at" nulls last, x."id"
    limit least(greatest(coalesce(open_engagements.page_size, 50), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

-- Recordings of calls and meetings: an ai-files file on an engagement,
-- waiting for its transcript until a transcriber saves one.
create table if not exists "better_supabase"."engagement_recordings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "engagement_id" uuid not null references "better_supabase"."engagements" ("id") on delete cascade,
  "file_id" uuid not null references "better_supabase"."ai_files" ("id") on delete cascade,
  "filename" text not null,
  "media_type" text not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'transcribed', 'failed')),
  "language" text,
  "duration_seconds" integer check ("duration_seconds" >= 0),
  "error" text,
  "model" text,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "transcribed_at" timestamptz,
  unique ("engagement_id", "file_id")
);
create index if not exists engagement_recordings_file_idx on "better_supabase"."engagement_recordings" ("file_id");
create index if not exists engagement_recordings_pending_idx on "better_supabase"."engagement_recordings" ("created_at") where "status" = 'pending';
alter table "better_supabase"."engagement_recordings" enable row level security;
revoke all on "better_supabase"."engagement_recordings" from anon, authenticated;
grant select on "better_supabase"."engagement_recordings" to authenticated;
grant all on "better_supabase"."engagement_recordings" to service_role;
drop policy if exists engagement_recordings_read on "better_supabase"."engagement_recordings";
create policy engagement_recordings_read on "better_supabase"."engagement_recordings" for select to authenticated
using (exists (select 1 from "better_supabase"."engagements" ex where ex."id" = "engagement_id"));

-- A transcript, one row per speaker turn, offsets in milliseconds from the
-- start of the recording.
create table if not exists "better_supabase"."engagement_transcript_segments" (
  "recording_id" uuid not null references "better_supabase"."engagement_recordings" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "position" integer not null check ("position" >= 1),
  "speaker" text,
  "speaker_user_id" uuid,
  "starts_ms" integer not null check ("starts_ms" >= 0),
  "ends_ms" integer not null,
  "text" text not null,
  "confidence" real check ("confidence" between 0 and 1),
  primary key ("recording_id", "position"),
  check ("ends_ms" >= "starts_ms")
);
alter table "better_supabase"."engagement_transcript_segments" enable row level security;
revoke all on "better_supabase"."engagement_transcript_segments" from anon, authenticated;
grant select on "better_supabase"."engagement_transcript_segments" to authenticated;
grant all on "better_supabase"."engagement_transcript_segments" to service_role;
drop policy if exists engagement_transcript_segments_read on "better_supabase"."engagement_transcript_segments";
create policy engagement_transcript_segments_read on "better_supabase"."engagement_transcript_segments" for select to authenticated
using (exists (select 1 from "better_supabase"."engagement_recordings" rx where rx."id" = "recording_id"));

-- Notes on an engagement: a summary and action items, written by an AI
-- note taker or a member. One row per engagement; saving replaces it.
create table if not exists "better_supabase"."engagement_notes" (
  "engagement_id" uuid primary key references "better_supabase"."engagements" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "summary" text not null check (length("summary") between 1 and 20000),
  "action_items" jsonb not null default '[]' check (jsonb_typeof("action_items") = 'array'),
  "model" text,
  "source" text not null default 'ai' check ("source" in ('ai', 'member')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."engagement_notes" enable row level security;
revoke all on "better_supabase"."engagement_notes" from anon, authenticated;
grant select on "better_supabase"."engagement_notes" to authenticated;
grant all on "better_supabase"."engagement_notes" to service_role;
drop policy if exists engagement_notes_read on "better_supabase"."engagement_notes";
create policy engagement_notes_read on "better_supabase"."engagement_notes" for select to authenticated
using (exists (select 1 from "better_supabase"."engagements" ex where ex."id" = "engagement_id"));

-- Attaches a ready ai-files file of the engagement's tenant as a recording.
-- The author, the owner and engagements.manage may attach; the file must be
-- the caller's own unless they manage engagements. With the jobs block a
-- transcription job goes on the engagements.transcribe queue.
create or replace function "better_supabase"."attach_engagement_recording"(engagement uuid, file uuid, language text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_type text;
  v_recording uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."engagements" x where x."id" = attach_engagement_recording.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if not exists (
    select 1 from "better_supabase"."ai_files" fx
    where fx."id" = attach_engagement_recording.file
      and fx."organization_id"::text = v_tenant::text
      and fx."status" = 'ready'
      and (auth.role() = 'service_role' or fx."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_tenant, 'engagements.manage'), false))
  ) then
    raise exception 'no such ready file in this organization' using errcode = 'P0002', hint = 'AI_FILE_NOT_FOUND';
  end if;
  insert into "better_supabase"."engagement_recordings" ("tenant_id", "engagement_id", "file_id", "filename", "media_type", "language", "created_by")
  select v_tenant, attach_engagement_recording.engagement, fx."id", fx."filename", fx."media_type", nullif(trim(attach_engagement_recording.language), ''), auth.uid()
  from "better_supabase"."ai_files" fx where fx."id" = attach_engagement_recording.file
  on conflict ("engagement_id", "file_id") do nothing
  returning "id" into v_recording;
  if v_recording is null then
    raise exception 'the file is already a recording of this engagement' using errcode = '23505', hint = 'ENGAGEMENT_RECORDING_EXISTS';
  end if;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = attach_engagement_recording.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.recorded', jsonb_build_object('organizationId', v_tenant, 'engagementId', attach_engagement_recording.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || attach_engagement_recording.engagement::text, (v_tenant::text)::text, null, 'better-supabase/activities');
  perform "better_supabase"."enqueue_job"(queue => 'engagements.transcribe', payload => jsonb_build_object('recordingId', v_recording), dedupe_key => 'engagements.transcribe:' || v_recording::text, dedupe_running => false);
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$$;
revoke execute on function "better_supabase"."attach_engagement_recording"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."attach_engagement_recording"(uuid, uuid, text) to authenticated, service_role;

-- An engagement's recordings, oldest first, as the caller may read them.
create or replace function "better_supabase"."engagement_recordings"(engagement uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") order by rx."created_at", rx."id"), '[]'::jsonb)
  from "better_supabase"."engagement_recordings" rx
  where rx."engagement_id" = engagement_recordings.engagement
$$;
revoke execute on function "better_supabase"."engagement_recordings"(uuid) from public, anon;
grant execute on function "better_supabase"."engagement_recordings"(uuid) to authenticated, service_role;

-- One recording, for the transcription job; null when the caller can't read it.
create or replace function "better_supabase"."get_engagement_recording"(recording uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at")
  from "better_supabase"."engagement_recordings" rx
  where rx."id" = get_engagement_recording.recording
$$;
revoke execute on function "better_supabase"."get_engagement_recording"(uuid) from public, anon;
grant execute on function "better_supabase"."get_engagement_recording"(uuid) to authenticated, service_role;

-- A transcript in order, after position after (0 for the start).
create or replace function "better_supabase"."engagement_transcript"(recording uuid, after integer, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(p.value order by p.position), '[]'::jsonb)
  from (
    select jsonb_build_object('position', sx."position", 'speaker', sx."speaker", 'speakerUserId', sx."speaker_user_id", 'startMs', sx."starts_ms", 'endMs', sx."ends_ms", 'text', sx."text", 'confidence', sx."confidence") as value, sx."position" as position
    from "better_supabase"."engagement_transcript_segments" sx
    where sx."recording_id" = engagement_transcript.recording
      and sx."position" > coalesce(engagement_transcript.after, 0)
    order by sx."position"
    limit least(greatest(coalesce(engagement_transcript.page_size, 500), 1), 5000)
  ) p
$$;
revoke execute on function "better_supabase"."engagement_transcript"(uuid, integer, integer) from public, anon;
grant execute on function "better_supabase"."engagement_transcript"(uuid, integer, integer) to authenticated, service_role;

-- Replaces a recording's transcript: segments is [{ speaker, speakerUserId,
-- startMs, endMs, text, confidence }] in order, attrs { language,
-- durationSeconds, model }. The service role (a transcription job) and
-- whoever may edit the engagement may save one.
create or replace function "better_supabase"."save_engagement_transcript"(recording uuid, segments jsonb, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recording uuid := save_engagement_transcript.recording;
  v_engagement uuid;
  v_tenant uuid;
  v_type text;
  v_item jsonb;
  v_position integer;
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select rx."engagement_id", rx."tenant_id", x."type" into v_engagement, v_tenant, v_type
  from "better_supabase"."engagement_recordings" rx
  join "better_supabase"."engagements" x on x."id" = rx."engagement_id"
  where rx."id" = v_recording and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false))
  for update of rx;
  if v_engagement is null then
    raise exception 'no such recording you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_RECORDING_NOT_FOUND';
  end if;
  if jsonb_typeof(save_engagement_transcript.segments) is distinct from 'array'
    or jsonb_array_length(save_engagement_transcript.segments) > 20000 then
    raise exception 'segments must be a list of at most 20000 { startMs, endMs, text }' using errcode = '22023', hint = 'ENGAGEMENT_TRANSCRIPT_INVALID';
  end if;
  for v_item, v_position in select value, ordinality from jsonb_array_elements(save_engagement_transcript.segments) with ordinality loop
    if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item -> 'text') is distinct from 'string'
      or jsonb_typeof(v_item -> 'startMs') is distinct from 'number'
      or jsonb_typeof(v_item -> 'endMs') is distinct from 'number'
      or (v_item ->> 'startMs')::numeric < 0
      or (v_item ->> 'endMs')::numeric < (v_item ->> 'startMs')::numeric
      or jsonb_typeof(coalesce(v_item -> 'confidence', 'null')) not in ('number', 'null') then
      raise exception 'segment % needs startMs <= endMs and a text', v_position using errcode = '22023', hint = 'ENGAGEMENT_TRANSCRIPT_INVALID';
    end if;
  end loop;
  delete from "better_supabase"."engagement_transcript_segments" sx where sx."recording_id" = v_recording;
  insert into "better_supabase"."engagement_transcript_segments" ("recording_id", "tenant_id", "position", "speaker", "speaker_user_id", "starts_ms", "ends_ms", "text", "confidence")
  select v_recording, v_tenant, i.ordinality::integer, nullif(i.value ->> 'speaker', ''), nullif(i.value ->> 'speakerUserId', '')::uuid,
    round((i.value ->> 'startMs')::numeric)::integer, round((i.value ->> 'endMs')::numeric)::integer, i.value ->> 'text', (i.value ->> 'confidence')::real
  from jsonb_array_elements(save_engagement_transcript.segments) with ordinality i;
  update "better_supabase"."engagement_recordings" rx set
    "status" = 'transcribed',
    "error" = null,
    "language" = coalesce(nullif(save_engagement_transcript.attrs ->> 'language', ''), rx."language"),
    "duration_seconds" = coalesce((save_engagement_transcript.attrs ->> 'durationSeconds')::integer, rx."duration_seconds"),
    "model" = coalesce(nullif(save_engagement_transcript.attrs ->> 'model', ''), rx."model"),
    "transcribed_at" = now()
  where rx."id" = v_recording;
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.transcribed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects, 'recordingId', v_recording), 'engagements/' || v_engagement::text, (v_tenant::text)::text, 'engagement.transcribed:' || v_recording::text || ':' || md5(save_engagement_transcript.segments::text), 'better-supabase/activities');
  return (select jsonb_build_object('id', rx."id", 'organizationId', rx."tenant_id", 'engagementId', rx."engagement_id", 'fileId', rx."file_id", 'filename', rx."filename", 'mediaType', rx."media_type", 'status', rx."status", 'language', rx."language", 'durationSeconds', rx."duration_seconds", 'error', rx."error", 'model', rx."model", 'segmentCount', (select count(*)::integer from "better_supabase"."engagement_transcript_segments" sc where sc."recording_id" = rx."id"), 'createdBy', rx."created_by", 'createdAt', rx."created_at", 'transcribedAt', rx."transcribed_at") from "better_supabase"."engagement_recordings" rx where rx."id" = v_recording);
end;
$$;
revoke execute on function "better_supabase"."save_engagement_transcript"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."save_engagement_transcript"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Marks a recording failed with the transcriber's error. Service only.
create or replace function "better_supabase"."fail_engagement_recording"(recording uuid, error text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with failed as (
    update "better_supabase"."engagement_recordings" rx set "status" = 'failed', "error" = left(fail_engagement_recording.error, 2000)
    where rx."id" = fail_engagement_recording.recording and rx."status" <> 'transcribed'
    returning 1
  )
  select exists (select 1 from failed)
$$;
revoke execute on function "better_supabase"."fail_engagement_recording"(uuid, text) from public, anon, authenticated;
grant execute on function "better_supabase"."fail_engagement_recording"(uuid, text) to service_role;

-- Recordings that wait for a transcript, oldest first, for a drain without
-- the jobs block. Service only.
create or replace function "better_supabase"."pending_engagement_recordings"(batch integer)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(p.id order by p.at), '{}')
  from (
    select rx."id" as id, rx."created_at" as at
    from "better_supabase"."engagement_recordings" rx
    where rx."status" = 'pending'
    order by rx."created_at"
    limit least(greatest(coalesce(pending_engagement_recordings.batch, 20), 1), 200)
  ) p
$$;
revoke execute on function "better_supabase"."pending_engagement_recordings"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."pending_engagement_recordings"(integer) to service_role;

-- Saves an engagement's notes: notes { summary, actionItems: [{ text,
-- ownerId, dueAt }], model, source }. Replaces earlier notes.
create or replace function "better_supabase"."save_engagement_notes"(engagement uuid, notes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_type text;
  v_summary text := nullif(trim(save_engagement_notes.notes ->> 'summary'), '');
  v_items jsonb := coalesce(save_engagement_notes.notes -> 'actionItems', '[]'::jsonb);
  v_subjects jsonb;
  v_first jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."type" into v_tenant, v_type
  from "better_supabase"."engagements" x where x."id" = save_engagement_notes.engagement and (auth.role() = 'service_role' or x."created_by" = auth.uid() or x."owner_user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.manage'), false));
  if v_tenant is null then
    raise exception 'no such engagement you can edit' using errcode = 'P0002', hint = 'ENGAGEMENT_NOT_FOUND';
  end if;
  if v_summary is null or length(v_summary) > 20000 then
    raise exception 'notes need a summary of at most 20000 characters' using errcode = '22023', hint = 'ENGAGEMENT_NOTES_INVALID';
  end if;
  if jsonb_typeof(v_items) <> 'array' or exists (
    select 1 from jsonb_array_elements(v_items) i
    where jsonb_typeof(i.value) <> 'object' or jsonb_typeof(i.value -> 'text') is distinct from 'string'
  ) then
    raise exception 'actionItems must be a list of { text }' using errcode = '22023', hint = 'ENGAGEMENT_NOTES_INVALID';
  end if;
  insert into "better_supabase"."engagement_notes" ("engagement_id", "tenant_id", "summary", "action_items", "model", "source", "created_by")
  values (save_engagement_notes.engagement, v_tenant, v_summary, v_items, nullif(save_engagement_notes.notes ->> 'model', ''),
    case when save_engagement_notes.notes ->> 'source' = 'member' then 'member' else 'ai' end, auth.uid())
  on conflict ("engagement_id") do update set
    "summary" = excluded."summary", "action_items" = excluded."action_items",
    "model" = excluded."model", "source" = excluded."source", "updated_at" = now();
  v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = save_engagement_notes.engagement), '[]'::jsonb);
  v_first := v_subjects -> 0;
  perform "better_supabase".emit_event('engagement.summarized', jsonb_build_object('organizationId', v_tenant, 'engagementId', save_engagement_notes.engagement, 'type', v_type, 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || save_engagement_notes.engagement::text, (v_tenant::text)::text, 'engagement.summarized:' || save_engagement_notes.engagement::text || ':' || md5(save_engagement_notes.notes::text), 'better-supabase/activities');
  return (select jsonb_build_object('engagementId', nx."engagement_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionItems', nx."action_items", 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."engagement_notes" nx where nx."engagement_id" = save_engagement_notes.engagement);
end;
$$;
revoke execute on function "better_supabase"."save_engagement_notes"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_engagement_notes"(uuid, jsonb) to authenticated, service_role;

-- An engagement with the transcripts of its recordings in order, for a note
-- taker: { engagement, segments: [{ recordingId, position, ... }] }. Null
-- when the caller can't read it.
create or replace function "better_supabase"."engagement_with_transcripts"(engagement uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'engagement', to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = x."id"), '[]'::jsonb), 'overdue', x."done_at" is null and x."due_at" < now()),
    'segments', coalesce((
      select jsonb_agg(jsonb_build_object('position', sx."position", 'speaker', sx."speaker", 'speakerUserId', sx."speaker_user_id", 'startMs', sx."starts_ms", 'endMs', sx."ends_ms", 'text', sx."text", 'confidence', sx."confidence") || jsonb_build_object('recordingId', rx."id") order by rx."created_at", rx."id", sx."position")
      from "better_supabase"."engagement_recordings" rx
      join "better_supabase"."engagement_transcript_segments" sx on sx."recording_id" = rx."id"
      where rx."engagement_id" = x."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."engagements" x
  where x."id" = engagement_with_transcripts.engagement
$$;
revoke execute on function "better_supabase"."engagement_with_transcripts"(uuid) from public, anon;
grant execute on function "better_supabase"."engagement_with_transcripts"(uuid) to authenticated, service_role;

-- An engagement's notes, or null.
create or replace function "better_supabase"."engagement_notes"(engagement uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('engagementId', nx."engagement_id", 'organizationId', nx."tenant_id", 'summary', nx."summary", 'actionItems', nx."action_items", 'model', nx."model", 'source', nx."source", 'createdBy', nx."created_by", 'createdAt', nx."created_at", 'updatedAt', nx."updated_at") from "better_supabase"."engagement_notes" nx where nx."engagement_id" = engagement_notes.engagement
$$;
revoke execute on function "better_supabase"."engagement_notes"(uuid) from public, anon;
grant execute on function "better_supabase"."engagement_notes"(uuid) to authenticated, service_role;

-- A meeting engagement for each confirmed booking (options.bookings), with
-- the external ref booking:<id>: moved when the booking moves, and closed
-- with the outcome cancelled when it is cancelled.
create or replace function "better_supabase"."bsb_booking_engagement"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ref text := 'booking:' || new."id"::text;
  v_tenant uuid := new."tenant_id";
  v_id uuid;
  v_inserted boolean;
  v_title text;
  v_owner uuid := new."created_by";
  v_person uuid;
  v_person_owner uuid;
  v_subjects jsonb;
  v_first jsonb;
begin
  if new."status" = 'confirmed' then
    if tg_op = 'UPDATE' and old."status" = 'confirmed' and old."during" = new."during" then
      return null;
    end if;
    select p."id", p."owner_user_id" into v_person, v_person_owner
    from "better_supabase"."people" p
    where p."tenant_id" = v_tenant and p."archived_at" is null and p."merged_into" is null
      and ((new."customer_user_id" is not null and p."user_id" = new."customer_user_id")
        or (new."customer_email" is not null and lower(p."email") = lower(new."customer_email")))
    order by (new."customer_user_id" is not null and p."user_id" = new."customer_user_id") desc, p."created_at"
    limit 1;
    v_owner := coalesce(v_owner, v_person_owner);
    select left(coalesce(sv."name", 'Booking') || coalesce(' with ' || nullif(trim(new."customer_name"), ''), ''), 500)
    into v_title
    from "better_supabase"."booking_services" sv where sv."id" = new."service_id";
    insert into "better_supabase"."engagements" ("tenant_id", "type", "title", "body", "owner_user_id", "due_at", "duration_seconds", "external_ref", "created_by")
    values (v_tenant, 'meeting', coalesce(v_title, 'Booking'), new."notes", v_owner, lower(new."during"),
      extract(epoch from upper(new."during") - lower(new."during"))::integer, v_ref, new."created_by")
    on conflict ("tenant_id", "external_ref") where "external_ref" is not null do update set
      "due_at" = excluded."due_at", "duration_seconds" = excluded."duration_seconds",
      "done_at" = null, "outcome" = null, "updated_at" = now()
    returning "id", (xmax = 0) into v_id, v_inserted;
    if v_person is not null then
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
      values (v_tenant, v_id, 'person', v_person::text, 1)
      on conflict do nothing;
      insert into "better_supabase"."engagement_subjects" ("tenant_id", "engagement_id", "subject_type", "subject_id", "position")
      select v_tenant, v_id, 'company', c."id"::text, 2
      from "better_supabase"."company_people" k
      join "better_supabase"."companies" c on c."id" = k."company_id"
      where k."person_id" = v_person and c."archived_at" is null
      order by k."is_primary" desc, k."created_at"
      limit 1
      on conflict do nothing;
    end if;
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
    if v_inserted then
      perform "better_supabase".emit_event('engagement.logged', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    else
      perform "better_supabase".emit_event('engagement.updated', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    end if;
  elsif new."status" = 'cancelled' and tg_op = 'UPDATE' and old."status" = 'confirmed' then
    update "better_supabase"."engagements" x set
      "done_at" = coalesce(new."cancelled_at", now()),
      "outcome" = left('cancelled' || coalesce(': ' || nullif(trim(new."cancel_reason"), ''), ''), 500),
      "updated_at" = now()
    where x."tenant_id" = v_tenant and x."external_ref" = v_ref and x."done_at" is null
    returning x."id" into v_id;
    if v_id is not null then
    v_subjects := coalesce((select jsonb_agg(jsonb_build_object('type', sx."subject_type", 'id', sx."subject_id") order by sx."position") from "better_supabase"."engagement_subjects" sx where sx."engagement_id" = v_id), '[]'::jsonb);
    v_first := v_subjects -> 0;
      perform "better_supabase".emit_event('engagement.completed', jsonb_build_object('organizationId', v_tenant, 'engagementId', v_id, 'type', 'meeting', 'subjectType', v_first ->> 'type', 'subjectId', v_first ->> 'id', 'subjects', v_subjects), 'engagements/' || v_id::text, (v_tenant::text)::text, null, 'better-supabase/activities');
    end if;
  end if;
  return null;
end;
$$;
revoke all on function "better_supabase"."bsb_booking_engagement"() from public, anon, authenticated;
drop trigger if exists bookings_engagement on "better_supabase"."bookings";
create trigger bookings_engagement
after insert or update of "status", "during" on "better_supabase"."bookings"
for each row execute function "better_supabase"."bsb_booking_engagement"();

-- blocks.activities.api: entry points for the Data API.
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

create or replace function "api"."log_engagement"(tenant uuid, attrs jsonb, subjects jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."log_engagement"($1, $2, $3) $$;
revoke execute on function "api"."log_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."log_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_engagement"(engagement uuid, attrs jsonb, subjects jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_engagement"($1, $2, $3) $$;
revoke execute on function "api"."update_engagement"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."update_engagement"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."complete_engagement"(engagement uuid, done boolean, outcome text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."complete_engagement"($1, $2, $3) $$;
revoke execute on function "api"."complete_engagement"(uuid, boolean, text) from public, anon;
grant execute on function "api"."complete_engagement"(uuid, boolean, text) to authenticated, service_role;

create or replace function "api"."delete_engagement"(engagement uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_engagement"($1) $$;
revoke execute on function "api"."delete_engagement"(uuid) from public, anon;
grant execute on function "api"."delete_engagement"(uuid) to authenticated, service_role;

create or replace function "api"."engagements_of"(subject_type text, subject_id text, types text[], before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."engagements_of"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."engagements_of"(text, text, text[], timestamptz, integer) from public, anon;
grant execute on function "api"."engagements_of"(text, text, text[], timestamptz, integer) to authenticated, service_role;

create or replace function "api"."next_engagement"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."next_engagement"($1, $2) $$;
revoke execute on function "api"."next_engagement"(text, text) from public, anon;
grant execute on function "api"."next_engagement"(text, text) to authenticated, service_role;

create or replace function "api"."open_engagements"(tenant uuid, owner uuid, due_before timestamptz, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_engagements"($1, $2, $3, $4) $$;
revoke execute on function "api"."open_engagements"(uuid, uuid, timestamptz, integer) from public, anon;
grant execute on function "api"."open_engagements"(uuid, uuid, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."attach_engagement_recording"(engagement uuid, file uuid, language text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."attach_engagement_recording"($1, $2, $3) $$;
revoke execute on function "api"."attach_engagement_recording"(uuid, uuid, text) from public, anon;
grant execute on function "api"."attach_engagement_recording"(uuid, uuid, text) to authenticated, service_role;

create or replace function "api"."engagement_recordings"(engagement uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."engagement_recordings"($1) $$;
revoke execute on function "api"."engagement_recordings"(uuid) from public, anon;
grant execute on function "api"."engagement_recordings"(uuid) to authenticated, service_role;

create or replace function "api"."get_engagement_recording"(recording uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_engagement_recording"($1) $$;
revoke execute on function "api"."get_engagement_recording"(uuid) from public, anon;
grant execute on function "api"."get_engagement_recording"(uuid) to authenticated, service_role;

create or replace function "api"."engagement_transcript"(recording uuid, after integer, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."engagement_transcript"($1, $2, $3) $$;
revoke execute on function "api"."engagement_transcript"(uuid, integer, integer) from public, anon;
grant execute on function "api"."engagement_transcript"(uuid, integer, integer) to authenticated, service_role;

create or replace function "api"."save_engagement_transcript"(recording uuid, segments jsonb, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_engagement_transcript"($1, $2, $3) $$;
revoke execute on function "api"."save_engagement_transcript"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."save_engagement_transcript"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."fail_engagement_recording"(recording uuid, error text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."fail_engagement_recording"($1, $2) $$;
revoke execute on function "api"."fail_engagement_recording"(uuid, text) from public, anon, authenticated;
grant execute on function "api"."fail_engagement_recording"(uuid, text) to service_role;

create or replace function "api"."pending_engagement_recordings"(batch integer)
returns uuid[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pending_engagement_recordings"($1) $$;
revoke execute on function "api"."pending_engagement_recordings"(integer) from public, anon, authenticated;
grant execute on function "api"."pending_engagement_recordings"(integer) to service_role;

create or replace function "api"."save_engagement_notes"(engagement uuid, notes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_engagement_notes"($1, $2) $$;
revoke execute on function "api"."save_engagement_notes"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_engagement_notes"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."engagement_with_transcripts"(engagement uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."engagement_with_transcripts"($1) $$;
revoke execute on function "api"."engagement_with_transcripts"(uuid) from public, anon;
grant execute on function "api"."engagement_with_transcripts"(uuid) to authenticated, service_role;

create or replace function "api"."engagement_notes"(engagement uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."engagement_notes"($1) $$;
revoke execute on function "api"."engagement_notes"(uuid) from public, anon;
grant execute on function "api"."engagement_notes"(uuid) to authenticated, service_role;

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
