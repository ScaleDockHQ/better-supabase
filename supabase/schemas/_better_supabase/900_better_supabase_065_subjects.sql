-- better-supabase module: subjects
-- @bsb-block subjects@1 managed
-- @bsb-hash sha256:f46746627f01270a11f83463532e647b9d366e65dd02aedebf26567ce07c13c9
-- The app-wide subject registry from config.subjects: subject_title, subject_url, subject_titles, can_subject, can_subject_for and record_summary for every registered type, my_work across the installed blocks, record teams (subject_members, add_subject_member, end_subject_member, list_subject_members, my_subjects) that grant subjects.<type>.team actions, read logging for types with subjects.<type>.auditReads (record_subject_read, subject_access_log), and Realtime presence on presence:<type>:<id> for readers of the subject.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."subject_members";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_members";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_members";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_members";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_members";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Record teams (subjects.<type>.team, ADR 0134): the users and teams on one
-- record, each with a role and the days the membership counts.
create table if not exists "better_supabase"."subject_members" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "team_id" uuid references "better_supabase"."teams" ("id") on delete cascade,
  "role" text not null default 'member',
  "starts_on" date,
  "ends_on" date,
  "ends_at" timestamptz,
  "emergency" boolean not null default false,
  "reason" text,
  "created_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  constraint subject_members_one_member check (("user_id" is null) <> ("team_id" is null)),
  constraint subject_members_dates check ("ends_on" is null or "starts_on" is null or "ends_on" >= "starts_on")
);
create unique index if not exists subject_members_user_key on "better_supabase"."subject_members" ("subject_type", "subject_id", "user_id", "role") where "user_id" is not null;
create unique index if not exists subject_members_team_key on "better_supabase"."subject_members" ("subject_type", "subject_id", "team_id", "role") where "team_id" is not null;
create index if not exists subject_members_user_idx on "better_supabase"."subject_members" ("user_id", "tenant_id");
create index if not exists subject_members_team_idx on "better_supabase"."subject_members" ("team_id");
alter table "better_supabase"."subject_members" add column if not exists "ends_at" timestamptz;
alter table "better_supabase"."subject_members" enable row level security;
revoke all on "better_supabase"."subject_members" from public, anon, authenticated;
grant select on "better_supabase"."subject_members" to authenticated;
grant all on "better_supabase"."subject_members" to service_role;

-- Whether the caller is on the record's team today, directly or through a
-- team. Reads past the table's policies; it answers for the caller only.
create or replace function "better_supabase"."is_subject_member"(subject_type text, subject_id text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  return exists (
    select 1 from "better_supabase"."subject_members" m
    where m."subject_type" = is_subject_member.subject_type
      and m."subject_id" = is_subject_member.subject_id
      and (m."user_id" = auth.uid() or (m."team_id" is not null and m."team_id" in (select "better_supabase"."team_ids_of"(auth.uid()))))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())
  );
end;
$$;
revoke execute on function "better_supabase"."is_subject_member"(text, text) from public, anon;
grant execute on function "better_supabase"."is_subject_member"(text, text) to authenticated, service_role;

-- Whether the caller is on the record's team today in one of roles, for a
-- read rule that only some roles pass. The caller only, like
-- is_subject_member.
create or replace function "better_supabase"."has_subject_role"(subject_type text, subject_id text, roles text[])
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or coalesce(cardinality(has_subject_role.roles), 0) = 0 then
    return false;
  end if;
  return exists (
    select 1 from "better_supabase"."subject_members" m
    where m."subject_type" = has_subject_role.subject_type
      and m."subject_id" = has_subject_role.subject_id
      and m."role" = any (has_subject_role.roles)
      and (m."user_id" = auth.uid() or (m."team_id" is not null and m."team_id" in (select "better_supabase"."team_ids_of"(auth.uid()))))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())
  );
end;
$$;
revoke execute on function "better_supabase"."has_subject_role"(text, text, text[]) from public, anon;
grant execute on function "better_supabase"."has_subject_role"(text, text, text[]) to authenticated, service_role;

-- The app's subject registry (config.subjects, ADR 0020). Each function runs
-- as the caller, so the subject table's own policies decide what is visible.
create or replace function "better_supabase"."subject_types"()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select '{message,conversation,channel,company,person,deal,course,post,activity,quote,work_item,employee,invoice,ledger_account,product,product_variant,rfq,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,compliance_policy,qualification_type,risk,case,inspection,inspection_program,inspection_finding,form,meeting,meeting_decision,maintenance_plan,dam_usage_right,lims_sample,tax_code,production_order,work_center,bank_account,care_plan,incident,content_entry,document,customer,drive_node,application,change_request,project,task}'::text[]
$$;
revoke execute on function "better_supabase"."subject_types"() from public, anon;
grant execute on function "better_supabase"."subject_types"() to authenticated, service_role;

create or replace function "better_supabase"."subject_title"(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_title.subject_type
    when 'message' then
      return (select s."body"::text from "better_supabase"."messages" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'conversation' then
      return (select s."title"::text from "better_supabase"."conversations" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'channel' then
      return (select s."name"::text from "better_supabase"."channels" s where s."id" = (subject_title.subject_id)::uuid);
    when 'company' then
      return (select s."name"::text from "better_supabase"."companies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'person' then
      return (select s."name"::text from "better_supabase"."people" s where s."id" = (subject_title.subject_id)::uuid);
    when 'deal' then
      return (select s."name"::text from "better_supabase"."deals" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'course' then
      return (select s."title"::text from "better_supabase"."courses" s where s."id" = (subject_title.subject_id)::uuid);
    when 'post' then
      return (select s."title"::text from "better_supabase"."posts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'activity', 'engagement' then
      return (select s."title"::text from "better_supabase"."activities" s where s."id" = (subject_title.subject_id)::uuid);
    when 'quote' then
      return (select s."title"::text from "better_supabase"."quotes" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_item' then
      return (select s."title"::text from "better_supabase"."work_items" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select s."name"::text from "better_supabase"."employees" s where s."id" = (subject_title.subject_id)::uuid);
    when 'invoice' then
      return (select s."title"::text from "better_supabase"."invoices" s where s."id" = (subject_title.subject_id)::uuid);
    when 'ledger_account' then
      return (select s."name"::text from "better_supabase"."ledger_accounts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product' then
      return (select s."title"::text from "better_supabase"."products" s where s."id" = (subject_title.subject_id)::uuid);
    when 'product_variant' then
      return (select s."sku"::text from "better_supabase"."product_variants" s where s."id" = (subject_title.subject_id)::uuid);
    when 'rfq' then
      return (select s."title"::text from "better_supabase"."rfqs" s where s."id" = (subject_title.subject_id)::uuid);
    when 'order' then
      return (select s."number"::text from "better_supabase"."orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'calendar_event' then
      return (select s."title"::text from "better_supabase"."calendar_events" s where s."id" = (subject_title.subject_id)::uuid);
    when 'booking' then
      return (select s."customer_name"::text from "better_supabase"."bookings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset' then
      return (select s."name"::text from "better_supabase"."assets" s where s."id" = (subject_title.subject_id)::uuid);
    when 'asset_location' then
      return (select s."name"::text from "better_supabase"."asset_locations" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lease' then
      return (select s."title"::text from "better_supabase"."leases" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_report' then
      return (select s."title"::text from "better_supabase"."expense_reports" s where s."id" = (subject_title.subject_id)::uuid);
    when 'expense_line' then
      return (select s."description"::text from "better_supabase"."expense_lines" s where s."id" = (subject_title.subject_id)::uuid);
    when 'donation_fund' then
      return (select s."name"::text from "better_supabase"."donation_funds" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_order' then
      return (select s."title"::text from "better_supabase"."work_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'shipment' then
      return (select s."reference"::text from "better_supabase"."shipments" s where s."id" = (subject_title.subject_id)::uuid);
    when 'contract' then
      return (select s."title"::text from "better_supabase"."contracts" s where s."id" = (subject_title.subject_id)::uuid);
    when 'control' then
      return (select s."title"::text from "better_supabase"."controls" s where s."id" = (subject_title.subject_id)::uuid);
    when 'compliance_policy', 'policy' then
      return (select s."title"::text from "better_supabase"."compliance_policies" s where s."id" = (subject_title.subject_id)::uuid);
    when 'qualification_type' then
      return (select s."name"::text from "better_supabase"."qualification_types" s where s."id" = (subject_title.subject_id)::uuid);
    when 'risk' then
      return (select s."title"::text from "better_supabase"."risks" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'case' then
      return (select s."title"::text from "better_supabase"."cases" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'inspection' then
      return (select s."title"::text from "better_supabase"."inspections" s where s."id" = (subject_title.subject_id)::uuid);
    when 'inspection_program' then
      return (select s."name"::text from "better_supabase"."inspection_programs" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'inspection_finding' then
      return (select s."title"::text from "better_supabase"."inspection_findings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'form' then
      return (select s."title"::text from "better_supabase"."forms" s where s."id" = (subject_title.subject_id)::uuid);
    when 'meeting' then
      return (select s."title"::text from "better_supabase"."meetings" s where s."id" = (subject_title.subject_id)::uuid);
    when 'meeting_decision' then
      return (select s."title"::text from "better_supabase"."meeting_decisions" s where s."id" = (subject_title.subject_id)::uuid);
    when 'maintenance_plan' then
      return (select s."title"::text from "better_supabase"."maintenance_plans" s where s."id" = (subject_title.subject_id)::uuid);
    when 'dam_usage_right' then
      return (select s."licensee"::text from "better_supabase"."dam_usage_rights" s where s."id" = (subject_title.subject_id)::uuid);
    when 'lims_sample' then
      return (select s."title"::text from "better_supabase"."lims_samples" s where s."id" = (subject_title.subject_id)::uuid);
    when 'tax_code' then
      return (select s."name"::text from "better_supabase"."tax_codes" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'production_order' then
      return (select s."number"::text from "better_supabase"."production_orders" s where s."id" = (subject_title.subject_id)::uuid);
    when 'work_center' then
      return (select s."name"::text from "better_supabase"."work_centers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'bank_account' then
      return (select s."name"::text from "better_supabase"."bank_accounts" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'care_plan' then
      return (select s."title"::text from "better_supabase"."care_plans" s where s."id" = (subject_title.subject_id)::uuid);
    when 'incident' then
      return (select s."title"::text from "better_supabase"."incidents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'content_entry' then
      return (select s."title"::text from "better_supabase"."content_entries" s where s."id" = (subject_title.subject_id)::uuid);
    when 'document' then
      return (select s."name"::text from "better_supabase"."documents" s where s."id" = (subject_title.subject_id)::uuid);
    when 'customer' then
      return (select s."name"::text from "public"."customers" s where s."id" = (subject_title.subject_id)::uuid and s."archived_at" is null);
    when 'drive_node' then
      return (select s."name"::text from "better_supabase"."drive_nodes" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'change_request' then
      return (select s."title"::text from "public"."change_requests" s where s."id" = (subject_title.subject_id)::uuid);
    when 'project' then
      return (select s."name"::text from "public"."projects" s where s."id" = (subject_title.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select s."title"::text from "public"."tasks" s where s."id" = (subject_title.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$$;
revoke execute on function "better_supabase"."subject_title"(text, text) from public, anon;
grant execute on function "better_supabase"."subject_title"(text, text) to authenticated, service_role;

create or replace function "better_supabase"."subject_url"(subject_type text, subject_id text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case subject_url.subject_type
    when 'company' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."companies" s where s."id" = (subject_url.subject_id)::uuid);
    when 'person' then
      return (select '/crm/contacts/' || s."id"::text from "better_supabase"."people" s where s."id" = (subject_url.subject_id)::uuid);
    when 'deal' then
      return (select '/crm/deals' from "better_supabase"."deals" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'work_item' then
      return (select '/work' from "better_supabase"."work_items" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'employee' then
      return (select '/people' from "better_supabase"."employees" s where s."id" = (subject_url.subject_id)::uuid);
    when 'product' then
      return (select '/shop' from "better_supabase"."products" s where s."id" = (subject_url.subject_id)::uuid);
    when 'customer' then
      return (select '/customers/' || s."id"::text from "public"."customers" s where s."id" = (subject_url.subject_id)::uuid and s."archived_at" is null);
    when 'application' then
      return (select '/people/hiring' from "better_supabase"."applications" s where s."id" = (subject_url.subject_id)::uuid);
    when 'change_request' then
      return (select '/change-requests/' || s."id"::text from "public"."change_requests" s where s."id" = (subject_url.subject_id)::uuid);
    when 'project' then
      return (select '/projects/' || s."id"::text from "public"."projects" s where s."id" = (subject_url.subject_id)::uuid and s."deleted_at" is null);
    when 'task' then
      return (select '/projects/' || s."project_id"::text from "public"."tasks" s where s."id" = (subject_url.subject_id)::uuid);
    else
      return null;
  end case;
  return null;
end;
$$;
revoke execute on function "better_supabase"."subject_url"(text, text) from public, anon;
grant execute on function "better_supabase"."subject_url"(text, text) to authenticated, service_role;

-- Titles and paths for many subjects in one call: refs is a JSON array of
-- { "type", "id" }, the result one of { type, id, title, url }. A row the
-- caller can't see, an unknown type or a soft-deleted row returns nothing.
create or replace function "better_supabase"."subject_titles"(refs jsonb)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  found jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(subject_titles.refs) is distinct from 'array' then
    raise exception 'refs must be a JSON array of { type, id }'
      using errcode = '22023', hint = 'SUBJECT_REFS_INVALID';
  end if;
  if jsonb_array_length(subject_titles.refs) > 500 then
    raise exception 'subject_titles takes at most 500 refs'
      using errcode = '22023', hint = 'SUBJECT_REFS_TOO_MANY';
  end if;
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'message', 'id', s."id"::text,
      'title', s."body"::text, 'url', null::text))
    from "better_supabase"."messages" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'message')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'conversation', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."conversations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'conversation')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'channel', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."channels" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'channel')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'company', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."companies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'company')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'person', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/contacts/' || s."id"::text))
    from "better_supabase"."people" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'person')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'deal', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/crm/deals'))
    from "better_supabase"."deals" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'deal')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'course', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."courses" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'course')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'post', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."posts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'post')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'activity', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."activities" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'activity')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'quote', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."quotes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'quote')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_item', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/work'))
    from "better_supabase"."work_items" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_item')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'employee', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/people'))
    from "better_supabase"."employees" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'employee')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'invoice', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."invoices" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'invoice')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'ledger_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."ledger_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'ledger_account')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/shop'))
    from "better_supabase"."products" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'product_variant', 'id', s."id"::text,
      'title', s."sku"::text, 'url', null::text))
    from "better_supabase"."product_variants" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'product_variant')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'rfq', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."rfqs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'rfq')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'order', 'id', s."id"::text,
      'title', s."number"::text, 'url', null::text))
    from "better_supabase"."orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'calendar_event', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."calendar_events" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'calendar_event')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'booking', 'id', s."id"::text,
      'title', s."customer_name"::text, 'url', null::text))
    from "better_supabase"."bookings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'booking')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."assets" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'asset_location', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."asset_locations" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'asset_location')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lease', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."leases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lease')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_report', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."expense_reports" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_report')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'expense_line', 'id', s."id"::text,
      'title', s."description"::text, 'url', null::text))
    from "better_supabase"."expense_lines" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'expense_line')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'donation_fund', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."donation_funds" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'donation_fund')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_order', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."work_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'shipment', 'id', s."id"::text,
      'title', s."reference"::text, 'url', null::text))
    from "better_supabase"."shipments" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'shipment')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'contract', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."contracts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'contract')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'control', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."controls" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'control')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'compliance_policy', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."compliance_policies" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'compliance_policy')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'qualification_type', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."qualification_types" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'qualification_type')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'risk', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."risks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'risk')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'case', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."cases" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'case')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspections" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_program', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."inspection_programs" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_program')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'inspection_finding', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."inspection_findings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'inspection_finding')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'form', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."forms" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'form')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meetings" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'meeting_decision', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."meeting_decisions" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'meeting_decision')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'maintenance_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."maintenance_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'maintenance_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'dam_usage_right', 'id', s."id"::text,
      'title', s."licensee"::text, 'url', null::text))
    from "better_supabase"."dam_usage_rights" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'dam_usage_right')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'lims_sample', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."lims_samples" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'lims_sample')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'tax_code', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."tax_codes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'tax_code')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'production_order', 'id', s."id"::text,
      'title', s."number"::text, 'url', null::text))
    from "better_supabase"."production_orders" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'production_order')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'work_center', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."work_centers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'work_center')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'bank_account', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."bank_accounts" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'bank_account')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'care_plan', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."care_plans" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'care_plan')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'incident', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."incidents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'incident')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'content_entry', 'id', s."id"::text,
      'title', s."title"::text, 'url', null::text))
    from "better_supabase"."content_entries" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'content_entry')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'document', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."documents" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'document')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'customer', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/customers/' || s."id"::text))
    from "public"."customers" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'customer')::uuid[]) and s."archived_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'drive_node', 'id', s."id"::text,
      'title', s."name"::text, 'url', null::text))
    from "better_supabase"."drive_nodes" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'drive_node')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'application', 'id', s."id"::text,
      'title', null::text, 'url', '/people/hiring'))
    from "better_supabase"."applications" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'application')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'change_request', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/change-requests/' || s."id"::text))
    from "public"."change_requests" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'change_request')::uuid[])), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'project', 'id', s."id"::text,
      'title', s."name"::text, 'url', '/projects/' || s."id"::text))
    from "public"."projects" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'project')::uuid[]) and s."deleted_at" is null), '[]'::jsonb);
  found := found || coalesce((
    select jsonb_agg(jsonb_build_object(
      'type', 'task', 'id', s."id"::text,
      'title', s."title"::text, 'url', '/projects/' || s."project_id"::text))
    from "public"."tasks" s
    where s."id" = any(array(select r ->> 'id' from jsonb_array_elements(subject_titles.refs) r where r ->> 'type' = 'task')::uuid[])), '[]'::jsonb);
  return found;
exception
  when invalid_text_representation then
    raise exception 'a subject id does not match its type''s id column'
      using errcode = '22023', hint = 'SUBJECT_ID_INVALID';
end;
$$;
revoke execute on function "better_supabase"."subject_titles"(jsonb) from public, anon;
grant execute on function "better_supabase"."subject_titles"(jsonb) to authenticated, service_role;

-- True when the caller can see the subject row and, for an action with a
-- key in config.subjects.<type>.permissions, holds that key in the
-- subject's tenant (or on the record, through the subject's scope), and the
-- action's check function, when it names one, returns true for the row.
create or replace function "better_supabase"."can_subject"(subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  case can_subject.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'channels.manage'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.manage'), false)
          else true
        end)
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.write'), false)
          else true
        end)
      );
    when 'activity', 'engagement' then
      return exists (
        select 1 from "better_supabase"."activities" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.write'), false)
          else true
        end)
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.write'), false)
          else true
        end)
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'rfq' then
      return exists (
        select 1 from "better_supabase"."rfqs" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.write'), false)
          else true
        end)
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.manage'), false)
          else true
        end)
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end)
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.manage'), false)
          else true
        end)
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."leases" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end)
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end)
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end)
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end)
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end)
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end)
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end)
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end)
      );
    when 'compliance_policy', 'policy' then
      return exists (
        select 1 from "better_supabase"."compliance_policies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end)
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.manage'), false)
          else true
        end)
      );
    when 'risk' then
      return exists (
        select 1 from "better_supabase"."risks" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.write'), false)
          else true
        end)
      );
    when 'case' then
      return exists (
        select 1 from "better_supabase"."cases" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.write'), false)
          else true
        end)
      );
    when 'inspection' then
      return exists (
        select 1 from "better_supabase"."inspections" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end)
      );
    when 'inspection_program' then
      return exists (
        select 1 from "better_supabase"."inspection_programs" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.manage'), false)
          else true
        end)
      );
    when 'inspection_finding' then
      return exists (
        select 1 from "better_supabase"."inspection_findings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end)
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.manage'), false)
          else true
        end)
      );
    when 'meeting' then
      return exists (
        select 1 from "better_supabase"."meetings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end)
      );
    when 'meeting_decision' then
      return exists (
        select 1 from "better_supabase"."meeting_decisions" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end)
      );
    when 'maintenance_plan' then
      return exists (
        select 1 from "better_supabase"."maintenance_plans" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.manage'), false)
          else true
        end)
      );
    when 'dam_usage_right' then
      return exists (
        select 1 from "better_supabase"."dam_usage_rights" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.write'), false)
          else true
        end)
      );
    when 'lims_sample' then
      return exists (
        select 1 from "better_supabase"."lims_samples" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.write'), false)
          else true
        end)
      );
    when 'tax_code' then
      return exists (
        select 1 from "better_supabase"."tax_codes" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.manage'), false)
          else true
        end)
      );
    when 'production_order' then
      return exists (
        select 1 from "better_supabase"."production_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.write'), false)
          else true
        end)
      );
    when 'work_center' then
      return exists (
        select 1 from "better_supabase"."work_centers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.manage'), false)
          else true
        end)
      );
    when 'bank_account' then
      return exists (
        select 1 from "better_supabase"."bank_accounts" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.manage'), false)
          else true
        end)
      );
    when 'care_plan' then
      return exists (
        select 1 from "better_supabase"."care_plans" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.write'), false)
          else true
        end)
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end)
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.write'), false)
          else true
        end)
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end)
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          when 'write' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then ((coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', s."id"::text))
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then coalesce("better_supabase"."drive_can_comment"(s."id"), false)
          when 'fields' then coalesce("better_supabase"."drive_node_writable"(s."id"), false)
          else true
        end)
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and true
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$$;
revoke execute on function "better_supabase"."can_subject"(text, text, text) from public, anon;
grant execute on function "better_supabase"."can_subject"(text, text, text) to authenticated, service_role;

-- A record page's header and tab badges in one call: the subject's title and
-- path, how many rows each named section has and whether any is newer than
-- seen_at. Runs as the caller, so each count is what the caller can read;
-- null when the caller can't read the subject. An unknown section is left out.
create or replace function "better_supabase"."record_summary"(subject_type text, subject_id text, sections text[], seen_at timestamptz default null)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_counts jsonb := '{}'::jsonb;
  v_unread jsonb := '{}'::jsonb;
  v_count bigint;
  v_latest timestamptz;
  v_seen timestamptz;
begin
  if coalesce(cardinality(record_summary.sections), 0) > 20 then
    raise exception 'record_summary takes at most 20 sections'
      using errcode = '22023', hint = 'RECORD_SECTIONS_TOO_MANY';
  end if;
  if not "better_supabase"."can_subject"(record_summary.subject_type, record_summary.subject_id, 'read') then
    return null;
  end if;
  perform "better_supabase"."record_subject_read"(record_summary.subject_type, record_summary.subject_id, null, 'subjects', 'record_summary');
  if 'comments' = any (record_summary.sections) then
    select count(*), max(x."sent_at")
      into v_count, v_latest
      from "better_supabase"."messages" x
      join "better_supabase"."conversations" c on c."id" = x."conversation_id"
        and c."kind" = 'subject'
      where c."subject_type"::text = record_summary.subject_type
        and c."subject_id"::text = record_summary.subject_id
        and x."sent_at" is not null and x."deleted_at" is null;
    v_seen := coalesce((select "better_supabase"."conversation_read_at"(c."id") from "better_supabase"."conversations" c
        where c."kind" = 'subject'
          and c."subject_type" = record_summary.subject_type
          and c."subject_id" = record_summary.subject_id), record_summary.seen_at);
    v_counts := v_counts || jsonb_build_object('comments', v_count);
    v_unread := v_unread || jsonb_build_object('comments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  if 'attachments' = any (record_summary.sections) then
    select count(*), max(x."uploaded_at")
      into v_count, v_latest
      from "better_supabase"."attachments" x
      where x."subject_type"::text = record_summary.subject_type
        and x."subject_id"::text = record_summary.subject_id
        and x."uploaded_at" is not null and x."status" <> 'infected';
    v_seen := record_summary.seen_at;
    v_counts := v_counts || jsonb_build_object('attachments', v_count);
    v_unread := v_unread || jsonb_build_object('attachments',
      v_seen is not null and v_latest is not null and v_latest > v_seen);
  end if;
  return jsonb_build_object(
    'type', record_summary.subject_type,
    'id', record_summary.subject_id,
    'title', "better_supabase"."subject_title"(record_summary.subject_type, record_summary.subject_id),
    'url', "better_supabase"."subject_url"(record_summary.subject_type, record_summary.subject_id),
    'counts', v_counts,
    'unread', v_unread);
end;
$$;
revoke execute on function "better_supabase"."record_summary"(text, text, text[], timestamptz) from public, anon;
grant execute on function "better_supabase"."record_summary"(text, text, text[], timestamptz) to authenticated, service_role;

-- can_subject for another user, for server code that decides who receives
-- an event. It reads the row past its policies and asks can_user for the
-- action's key in config.subjects.<type>.permissions, so an action without
-- a key is false and a share-link grant never counts. A provider that
-- can't answer for others (no idsWithFor) gives false.
create or replace function "better_supabase"."can_subject_for"(member uuid, subject_type text, subject_id text, action text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  case can_subject_for.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'channels.manage'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contacts.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.manage'), false)
          else false
        end
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.write'), false)
          else false
        end
      );
    when 'activity', 'engagement' then
      return exists (
        select 1 from "better_supabase"."activities" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'activities.write'), false)
          else false
        end
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tasks.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.write'), false)
          else false
        end
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.manage'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'rfq' then
      return exists (
        select 1 from "better_supabase"."rfqs" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'rfqs.write'), false)
          else false
        end
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.manage'), false)
          else false
        end
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.write'), false)
          else false
        end
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.manage'), false)
          else false
        end
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."leases" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.manage'), false)
          else false
        end
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          else false
        end
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.submit'), false)
          else false
        end
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.manage'), false)
          else false
        end
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.manage'), false)
          else false
        end
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.manage'), false)
          else false
        end
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.write'), false)
          else false
        end
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.manage'), false)
          else false
        end
      );
    when 'compliance_policy', 'policy' then
      return exists (
        select 1 from "better_supabase"."compliance_policies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'compliance.manage'), false)
          else false
        end
      );
    when 'qualification_type' then
      return exists (
        select 1 from "better_supabase"."qualification_types" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'qualifications.manage'), false)
          else false
        end
      );
    when 'risk' then
      return exists (
        select 1 from "better_supabase"."risks" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'risks.write'), false)
          else false
        end
      );
    when 'case' then
      return exists (
        select 1 from "better_supabase"."cases" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'cases.write'), false)
          else false
        end
      );
    when 'inspection' then
      return exists (
        select 1 from "better_supabase"."inspections" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.write'), false)
          else false
        end
      );
    when 'inspection_program' then
      return exists (
        select 1 from "better_supabase"."inspection_programs" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.manage'), false)
          else false
        end
      );
    when 'inspection_finding' then
      return exists (
        select 1 from "better_supabase"."inspection_findings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'inspections.write'), false)
          else false
        end
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.manage'), false)
          else false
        end
      );
    when 'meeting' then
      return exists (
        select 1 from "better_supabase"."meetings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.write'), false)
          else false
        end
      );
    when 'meeting_decision' then
      return exists (
        select 1 from "better_supabase"."meeting_decisions" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'meetings.write'), false)
          else false
        end
      );
    when 'maintenance_plan' then
      return exists (
        select 1 from "better_supabase"."maintenance_plans" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'maintenance.manage'), false)
          else false
        end
      );
    when 'dam_usage_right' then
      return exists (
        select 1 from "better_supabase"."dam_usage_rights" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dam.write'), false)
          else false
        end
      );
    when 'lims_sample' then
      return exists (
        select 1 from "better_supabase"."lims_samples" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'lims.write'), false)
          else false
        end
      );
    when 'tax_code' then
      return exists (
        select 1 from "better_supabase"."tax_codes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'tax.manage'), false)
          else false
        end
      );
    when 'production_order' then
      return exists (
        select 1 from "better_supabase"."production_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.write'), false)
          else false
        end
      );
    when 'work_center' then
      return exists (
        select 1 from "better_supabase"."work_centers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'manufacturing.manage'), false)
          else false
        end
      );
    when 'bank_account' then
      return exists (
        select 1 from "better_supabase"."bank_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'banking.manage'), false)
          else false
        end
      );
    when 'care_plan' then
      return exists (
        select 1 from "better_supabase"."care_plans" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'care_plans.write'), false)
          else false
        end
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.write'), false)
          else false
        end
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.write'), false)
          else false
        end
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.write'), false)
          else false
        end
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then (coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false) or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'customer'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."organization_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          when 'write' then (coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false) or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'customer'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."organization_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then (false or exists (
            select 1 from "better_supabase"."subject_members" m
            where m."subject_type" = 'drive_node'
              and m."subject_id" = s."id"::text
              and m."tenant_id" = s."tenant_id"
              and (m."user_id" = can_subject_for.member or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = can_subject_for.member)))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())))
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then false
          when 'fields' then false
          else false
        end
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and false
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$$;
revoke execute on function "better_supabase"."can_subject_for"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."can_subject_for"(uuid, text, text, text) to service_role;

-- A caller reads their own record team rows, those of their teams, every row
-- of a tenant where they hold subjects.manage, and the team of a record they
-- can read.
drop policy if exists subject_members_read on "better_supabase"."subject_members";
create policy subject_members_read on "better_supabase"."subject_members"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or ("team_id" is not null and "team_id" in (select "better_supabase"."team_ids_of"((select auth.uid()))))
    or "tenant_id" in (select better_supabase.tenant_ids_with('subjects.manage'))
    or coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

-- Puts a user or a team on a record's team, or reopens their membership in
-- that role with the new dates. Needs subjects.manage in the record's tenant,
-- or can_subject(..., 'manage') on a type that declares a manage action.
create or replace function "better_supabase"."add_subject_member"(subject_type text, subject_id text, user_id uuid default null, team_id uuid default null, role text default 'member', starts_on date default null, ends_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_row "better_supabase"."subject_members";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (add_subject_member.subject_type = any (array['customer', 'drive_node']::text[])) then
    raise exception 'this subject type has no record team (subjects.<type>.team)' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if (add_subject_member.user_id is null) = (add_subject_member.team_id is null) then
    raise exception 'pass exactly one of user_id and team_id' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.role is null or not (add_subject_member.role = any ('{lead,member}'::text[])) then
    raise exception 'role must be one of lead, member' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.ends_on < add_subject_member.starts_on then
    raise exception 'ends_on is before starts_on' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  begin
    case add_subject_member.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (add_subject_member.subject_id)::uuid and s."archived_at" is null;
    when 'drive_node' then
      select s."tenant_id" into v_tenant from "better_supabase"."drive_nodes" s
      where s."id" = (add_subject_member.subject_id)::uuid and s."deleted_at" is null;
      else
        v_tenant := null;
    end case;
  exception
    when invalid_text_representation then
      raise exception 'the subject id does not match its type''s id column' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end;
  if v_tenant is null then
    raise exception 'subject not found' using errcode = 'P0002', hint = 'SUBJECT_MEMBER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or coalesce(better_supabase.can('tenant', v_tenant, 'subjects.manage'), false)
      or (add_subject_member.subject_type = any (array[]::text[]) and coalesce("better_supabase"."can_subject"(add_subject_member.subject_type, add_subject_member.subject_id, 'manage'), false))) then
    raise exception 'not allowed to manage this record''s team' using errcode = '42501', hint = 'SUBJECT_MEMBER_FORBIDDEN';
  end if;
  if add_subject_member.user_id is not null and not exists (
    select 1 from "public"."memberships" om
    where om."organization_id" = v_tenant
      and om."user_id" = add_subject_member.user_id
  ) then
    raise exception 'user is not a member of the record''s tenant' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.team_id is not null and not exists (
    select 1 from "better_supabase"."teams" tt
    where tt."id" = add_subject_member.team_id
      and tt."tenant_id" = v_tenant
  ) then
    raise exception 'team is not in the record''s tenant' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  if add_subject_member.user_id is not null then
    insert into "better_supabase"."subject_members" ("tenant_id", "subject_type", "subject_id", "user_id", "role", "starts_on", "ends_on", "created_by")
    values (v_tenant, add_subject_member.subject_type, add_subject_member.subject_id, add_subject_member.user_id, add_subject_member.role, add_subject_member.starts_on, add_subject_member.ends_on, auth.uid())
    on conflict ("subject_type", "subject_id", "user_id", "role") where "user_id" is not null
    do update set "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on"
    returning * into v_row;
  else
    insert into "better_supabase"."subject_members" ("tenant_id", "subject_type", "subject_id", "team_id", "role", "starts_on", "ends_on", "created_by")
    values (v_tenant, add_subject_member.subject_type, add_subject_member.subject_id, add_subject_member.team_id, add_subject_member.role, add_subject_member.starts_on, add_subject_member.ends_on, auth.uid())
    on conflict ("subject_type", "subject_id", "team_id", "role") where "team_id" is not null
    do update set "starts_on" = excluded."starts_on", "ends_on" = excluded."ends_on"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('subject_member.added', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on"), 'subjects/' || v_row."subject_type" || '/' || v_row."subject_id", (v_row."tenant_id")::text, null, 'better-supabase/subjects');
  perform better_supabase.audit_event(
    event_type => 'subject_member.added',
    category => 'access',
    target_type => 'subject_member',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on")
  );
  return jsonb_build_object(
      'id', v_row."id", 'organizationId', v_row."tenant_id",
      'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id",
      'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role",
      'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'endsAt', v_row."ends_at",
      'emergency', v_row."emergency", 'reason', v_row."reason",
      'active', (v_row."starts_on" is null or v_row."starts_on" <= current_date)
        and (v_row."ends_on" is null or v_row."ends_on" >= current_date)
        and (v_row."ends_at" is null or v_row."ends_at" > now()),
      'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."add_subject_member"(text, text, uuid, uuid, text, date, date) from public, anon;
grant execute on function "better_supabase"."add_subject_member"(text, text, uuid, uuid, text, date, date) to authenticated, service_role;

-- Ends a membership: it counts through ends_on (today by default), so access
-- stops the next day. The same callers as add_subject_member.
create or replace function "better_supabase"."end_subject_member"(member_id uuid, ends_on date default current_date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_members";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."subject_members" m where m."id" = end_subject_member.member_id;
  if not found then
    raise exception 'record team member not found' using errcode = 'P0002', hint = 'SUBJECT_MEMBER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'subjects.manage'), false)
      or (v_row."subject_type" = any (array[]::text[]) and coalesce("better_supabase"."can_subject"(v_row."subject_type", v_row."subject_id", 'manage'), false))) then
    raise exception 'not allowed to manage this record''s team' using errcode = '42501', hint = 'SUBJECT_MEMBER_FORBIDDEN';
  end if;
  if end_subject_member.ends_on is null or end_subject_member.ends_on < v_row."starts_on" then
    raise exception 'ends_on is missing or before starts_on' using errcode = '22023', hint = 'SUBJECT_MEMBER_INVALID';
  end if;
  update "better_supabase"."subject_members" m set "ends_on" = end_subject_member.ends_on
  where m."id" = end_subject_member.member_id
  returning * into v_row;
  perform "better_supabase".emit_event('subject_member.ended', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on"), 'subjects/' || v_row."subject_type" || '/' || v_row."subject_id", (v_row."tenant_id")::text, null, 'better-supabase/subjects');
  perform better_supabase.audit_event(
    event_type => 'subject_member.ended',
    category => 'access',
    target_type => 'subject_member',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on")
  );
  return jsonb_build_object(
      'id', v_row."id", 'organizationId', v_row."tenant_id",
      'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id",
      'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role",
      'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'endsAt', v_row."ends_at",
      'emergency', v_row."emergency", 'reason', v_row."reason",
      'active', (v_row."starts_on" is null or v_row."starts_on" <= current_date)
        and (v_row."ends_on" is null or v_row."ends_on" >= current_date)
        and (v_row."ends_at" is null or v_row."ends_at" > now()),
      'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."end_subject_member"(uuid, date) from public, anon;
grant execute on function "better_supabase"."end_subject_member"(uuid, date) to authenticated, service_role;

-- The record's team, current and past, for a caller who can read the record
-- (the table's policy decides). Leads first, then by when they joined.
create or replace function "better_supabase"."list_subject_members"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m."id", 'organizationId', m."tenant_id",
      'subjectType', m."subject_type", 'subjectId', m."subject_id",
      'userId', m."user_id", 'teamId', m."team_id", 'role', m."role",
      'startsOn', m."starts_on", 'endsOn', m."ends_on", 'endsAt', m."ends_at",
      'emergency', m."emergency", 'reason', m."reason",
      'active', (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now()),
      'createdBy', m."created_by", 'createdAt', m."created_at")
    order by m."role", m."created_at", m."id"), '[]'::jsonb)
  from "better_supabase"."subject_members" m
  where m."subject_type" = list_subject_members.subject_type
    and m."subject_id" = list_subject_members.subject_id;
$$;
revoke execute on function "better_supabase"."list_subject_members"(text, text) from public, anon;
grant execute on function "better_supabase"."list_subject_members"(text, text) to authenticated, service_role;

-- The records whose team the caller is on today in tenant, by type and id,
-- with their roles, a page at a time: cursor is the last item's
-- "<type>:<id>", and nextCursor is null on the last page.
create or replace function "better_supabase"."my_subjects"(tenant uuid, subject_type text default null, page_size integer default 100, cursor text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
  v_size integer := least(greatest(coalesce(my_subjects.page_size, 100), 1), 200);
  v_after_type text := split_part(my_subjects.cursor, ':', 1);
  v_after_id text := substr(my_subjects.cursor, length(split_part(my_subjects.cursor, ':', 1)) + 2);
  v_items jsonb;
  v_count integer;
begin
  if v_me is null then
    return jsonb_build_object('items', '[]'::jsonb, 'nextCursor', null);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'subjectType', p.subject_type, 'subjectId', p.subject_id,
      'organizationId', p.tenant, 'roles', p.roles, 'endsOn', p.ends_on,
      'emergency', p.emergency,
      'title', "better_supabase"."subject_title"(p.subject_type, p.subject_id),
      'url', "better_supabase"."subject_url"(p.subject_type, p.subject_id))
    order by p.subject_type, p.subject_id), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select m."subject_type" as subject_type, m."subject_id" as subject_id,
      min(m."tenant_id"::text) as tenant,
      jsonb_agg(distinct m."role") as roles,
      case when bool_or(m."ends_on" is null) then null else max(m."ends_on") end as ends_on,
      bool_or(m."emergency") as emergency
    from "better_supabase"."subject_members" m
    where m."tenant_id" = my_subjects.tenant
      and (my_subjects.subject_type is null or m."subject_type" = my_subjects.subject_type)
      and (my_subjects.cursor is null
        or (m."subject_type", m."subject_id") > (v_after_type, v_after_id))
      and (m."user_id" = v_me or (m."team_id" is not null and m."team_id" in (select "better_supabase"."team_ids_of"(v_me))))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())
    group by m."subject_type", m."subject_id"
    order by m."subject_type", m."subject_id"
    limit v_size
  ) p;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_size
      then (v_items -> -1 ->> 'subjectType') || ':' || (v_items -> -1 ->> 'subjectId')
      else null end);
end;
$$;
revoke execute on function "better_supabase"."my_subjects"(uuid, text, integer, text) from public, anon;
grant execute on function "better_supabase"."my_subjects"(uuid, text, integer, text) to authenticated, service_role;

-- The tenant of a record whose type has a team; null for another type or a
-- missing row.
create or replace function "better_supabase"."record_team_tenant"(subject_type text, subject_id text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  case record_team_tenant.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (record_team_tenant.subject_id)::uuid and s."archived_at" is null;
    when 'drive_node' then
      select s."tenant_id" into v_tenant from "better_supabase"."drive_nodes" s
      where s."id" = (record_team_tenant.subject_id)::uuid and s."deleted_at" is null;
    else
      v_tenant := null;
  end case;
  return v_tenant;
exception
  when invalid_text_representation then
    return null;
end;
$$;
revoke execute on function "better_supabase"."record_team_tenant"(text, text) from public, anon, authenticated;

-- The users who lead a record's team today, directly or through a team.
create or replace function "better_supabase"."record_team_leads"(subject_type text, subject_id text)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct l.id), '{}'::uuid[])
  from (
    select m."user_id" as id from "better_supabase"."subject_members" m
    where m."subject_type" = record_team_leads.subject_type
      and m."subject_id" = record_team_leads.subject_id
      and m."role" = 'lead' and m."user_id" is not null
      and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())
    union
    select tm."user_id" from "better_supabase"."subject_members" m
    join "better_supabase"."team_members" tm on tm."team_id" = m."team_id"
    where m."subject_type" = record_team_leads.subject_type
      and m."subject_id" = record_team_leads.subject_id
      and m."role" = 'lead' and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())
  ) l;
$$;
revoke execute on function "better_supabase"."record_team_leads"(text, text) from public, anon, authenticated;

-- Puts a user on a record's team until ends_at, for an approved request or an
-- emergency. A membership that already counts without an end is left alone,
-- and the result is null, so ending the request never closes it.
create or replace function "better_supabase"."grant_subject_member"(subject_type text, subject_id text, user_id uuid, ends_at timestamptz, emergency boolean, reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid := "better_supabase"."record_team_tenant"(grant_subject_member.subject_type, grant_subject_member.subject_id);
  v_row "better_supabase"."subject_members";
begin
  if v_tenant is null then
    raise exception 'subject not found' using errcode = 'P0002', hint = 'SUBJECT_MEMBER_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."subject_members" m
  where m."subject_type" = grant_subject_member.subject_type
      and m."subject_id" = grant_subject_member.subject_id
    and m."user_id" = grant_subject_member.user_id and m."role" = 'member'
    and m."ends_on" is null and m."ends_at" is null and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now());
  if found then
    return null;
  end if;
  insert into "better_supabase"."subject_members" ("tenant_id", "subject_type", "subject_id", "user_id", "role", "ends_on", "ends_at", "emergency", "reason", "created_by")
  values (v_tenant, grant_subject_member.subject_type, grant_subject_member.subject_id, grant_subject_member.user_id, 'member', grant_subject_member.ends_at::date, grant_subject_member.ends_at, coalesce(grant_subject_member.emergency, false), grant_subject_member.reason, auth.uid())
  on conflict ("subject_type", "subject_id", "user_id", "role") where "user_id" is not null
  do update set "starts_on" = null, "ends_on" = excluded."ends_on", "ends_at" = excluded."ends_at",
    "emergency" = excluded."emergency", "reason" = excluded."reason"
  returning * into v_row;
  perform "better_supabase".emit_event('subject_member.added', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on"), 'subjects/' || v_row."subject_type" || '/' || v_row."subject_id", (v_row."tenant_id")::text, null, 'better-supabase/subjects');
  perform better_supabase.audit_event(
    event_type => 'subject_member.added',
    category => 'access',
    target_type => 'subject_member',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on")
  );
  return v_row."id";
end;
$$;
revoke execute on function "better_supabase"."grant_subject_member"(text, text, uuid, timestamptz, boolean, text) from public, anon, authenticated;

-- Ends a granted membership now, when its request ends early.
create or replace function "better_supabase"."close_subject_member"(member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."subject_members";
begin
  update "better_supabase"."subject_members" m set "ends_at" = now()
  where m."id" = close_subject_member.member_id
    and (m."ends_at" is null or m."ends_at" > now())
  returning * into v_row;
  if found then
    perform "better_supabase".emit_event('subject_member.ended', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on"), 'subjects/' || v_row."subject_type" || '/' || v_row."subject_id", (v_row."tenant_id")::text, null, 'better-supabase/subjects');
  perform better_supabase.audit_event(
    event_type => 'subject_member.ended',
    category => 'access',
    target_type => 'subject_member',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'userId', v_row."user_id", 'teamId', v_row."team_id", 'role', v_row."role", 'endsOn', v_row."ends_on")
  );
  end if;
end;
$$;
revoke execute on function "better_supabase"."close_subject_member"(uuid) from public, anon, authenticated;

-- Logs that the caller read a record whose type has auditReads (category
-- read, event subject.accessed), with the NEN 7513 fields. Another type, a
-- missing record, a record the caller can't read or a call without a user
-- logs nothing. A read within 60 seconds of the caller's last
-- logged read of the record (reads.collapseSeconds) writes no new entry,
-- unless it gives another purpose or only one of the two was under emergency
-- access.
create or replace function "better_supabase"."record_subject_read"(subject_type text, subject_id text, purpose text default null, block_name text default null, function_name text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_emergency boolean;
  v_purpose text := nullif(btrim(record_subject_read.purpose), '');
begin
  if auth.uid() is null or not (record_subject_read.subject_type = any ('{customer}'::text[])) then
    return;
  end if;
  if length(v_purpose) > 500 then
    raise exception 'purpose takes at most 500 characters' using errcode = '22023', hint = 'SUBJECT_READ_INVALID';
  end if;
  begin
  case record_subject_read.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (record_subject_read.subject_id)::uuid and s."archived_at" is null;
    else
      v_tenant := null;
  end case;
  exception
    when invalid_text_representation then
      return;
  end;
  if v_tenant is null
    or not coalesce("better_supabase"."can_subject"(record_subject_read.subject_type, record_subject_read.subject_id, 'read'), false) then
    return;
  end if;
  v_emergency := exists (
    select 1 from "better_supabase"."subject_members" m
    where m."subject_type" = record_subject_read.subject_type
        and m."subject_id" = record_subject_read.subject_id
        and m."tenant_id" = v_tenant
      and m."emergency"
      and (m."user_id" = auth.uid() or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = auth.uid())))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now())
  );
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('better_supabase.record_subject_read'),
    pg_catalog.hashtext(auth.uid()::text || ':' || record_subject_read.subject_type || ':' || record_subject_read.subject_id));
  if exists (
    select 1 from "better_supabase"."audit_events" l
    where l."table_name" is null
        and l."record_id" = record_subject_read.subject_id
        and l."event_type" = 'subject.accessed'
        and l."organization_id" = v_tenant
        and l."metadata" ->> 'subjectType' = record_subject_read.subject_type
      and l."actor_id" = auth.uid()
      and l."occurred_at" > now() - make_interval(secs => 60)
      and coalesce((l."metadata" ->> 'emergency')::boolean, false) = v_emergency
      and l."metadata" ->> 'purpose' is not distinct from v_purpose
  ) then
    return;
  end if;
  perform better_supabase.audit_event(
    event_type => 'subject.accessed',
    category => 'read',
    target_type => 'subject',
    record_id => record_subject_read.subject_id,
    summary => 'Read ' || record_subject_read.subject_type || ' ' || record_subject_read.subject_id,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'subjectType', record_subject_read.subject_type, 'subjectId', record_subject_read.subject_id, 'purpose', v_purpose, 'emergency', v_emergency, 'block', record_subject_read.block_name, 'function', record_subject_read.function_name)
  );
end;
$$;
revoke execute on function "better_supabase"."record_subject_read"(text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."record_subject_read"(text, text, text, text, text) to authenticated, service_role;

-- Who read a record and when, newest first: the subject.accessed entries of
-- the audit log since `since`. The holders of audit.read in
-- its tenant, the record team's leads today, the record's own guest party
-- and a representative with act authority may ask.
create or replace function "better_supabase"."subject_access_log"(subject_type text, subject_id text, since timestamptz default null, max_rows integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (subject_access_log.subject_type = any ('{customer}'::text[])) then
    raise exception 'this subject type does not log reads' using errcode = '22023', hint = 'SUBJECT_READ_INVALID';
  end if;
  begin
  case subject_access_log.subject_type
    when 'customer' then
      select s."organization_id" into v_tenant from "public"."customers" s
      where s."id" = (subject_access_log.subject_id)::uuid and s."archived_at" is null;
    else
      v_tenant := null;
  end case;
  exception
    when invalid_text_representation then
      v_tenant := null;
  end;
  if v_tenant is null then
    raise exception 'subject not found' using errcode = 'P0002', hint = 'SUBJECT_READ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or coalesce(better_supabase.can('tenant', v_tenant, 'audit.read'), false)
    or exists (
      select 1 from "better_supabase"."subject_members" m
      where m."subject_type" = subject_access_log.subject_type
        and m."subject_id" = subject_access_log.subject_id
        and m."tenant_id" = v_tenant
        and m."role" = 'lead'
        and (m."user_id" = auth.uid() or (m."team_id" is not null and exists (
          select 1 from "better_supabase"."team_members" tm
          where tm."team_id" = m."team_id"
            and tm."user_id" = auth.uid())))
        and (m."starts_on" is null or m."starts_on" <= current_date)
        and (m."ends_on" is null or m."ends_on" >= current_date)
        and (m."ends_at" is null or m."ends_at" > now()))
    or ((v_tenant)::text, (subject_access_log.subject_type)::text, (subject_access_log.subject_id)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
    or exists (
      select 1 from "better_supabase"."relations" r
      where r."kind" = 'represents' and r."source_type" = 'person'
        and r."tenant_id"::text = v_tenant::text
        and r."target_type" = subject_access_log.subject_type and r."target_id" = subject_access_log.subject_id
        and r."data" ->> 'authority' = 'act'
        and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
        and ((v_tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) then
    raise exception 'you may not see who read this record' using errcode = '42501', hint = 'SUBJECT_READ_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(e.entry order by e.at desc), '[]'::jsonb)
    from (
      select jsonb_build_object(
      'id', l."id"::text,
      'actorId', l."actor_id",
      'actorName', (select coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', u.email::text) from auth.users u where u.id = l."actor_id"),
      'at', l."occurred_at",
      'purpose', l."metadata" ->> 'purpose',
      'emergency', coalesce((l."metadata" ->> 'emergency')::boolean, false),
      'block', l."metadata" ->> 'block',
      'function', l."metadata" ->> 'function') as entry, l."occurred_at" as at
      from "better_supabase"."audit_events" l
      where l."table_name" is null
        and l."record_id" = subject_access_log.subject_id
        and l."event_type" = 'subject.accessed'
        and l."organization_id" = v_tenant
        and l."metadata" ->> 'subjectType' = subject_access_log.subject_type
        and (subject_access_log.since is null or l."occurred_at" >= subject_access_log.since)
      order by l."occurred_at" desc
      limit least(greatest(coalesce(subject_access_log.max_rows, 100), 1), 500)
    ) e
  );
end;
$$;
revoke execute on function "better_supabase"."subject_access_log"(text, text, timestamptz, integer) from public, anon;
grant execute on function "better_supabase"."subject_access_log"(text, text, timestamptz, integer) to authenticated, service_role;

-- The caller's own reminders sent in the last week, for my_work. Reminders
-- have no read policy, so this reads them past it, keeping only the caller's.
create or replace function "better_supabase"."my_reminders_due"(tenant uuid default null)
returns table (reminder uuid, subject_type text, subject_id text, at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id", r."subject_type"::text,
    r."subject_id"::text, max(d."occurrence_at")
  from "better_supabase"."reminders" r
  join "better_supabase"."reminder_deliveries" d on d."reminder_id" = r."id"
  where r."user_id" = (select auth.uid())
    and (my_reminders_due.tenant is null or r."tenant_id" = my_reminders_due.tenant)
    and d."sent_at" > now() - interval '7 days'
  group by 1, 2, 3
$$;
revoke execute on function "better_supabase"."my_reminders_due"(uuid) from public, anon;
grant execute on function "better_supabase"."my_reminders_due"(uuid) to authenticated, service_role;

-- What waits on the caller across the installed blocks, newest first. Runs as
-- the caller, so each row is one they can read.
create or replace function "better_supabase"."my_work"(tenant uuid default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'kind', w.kind,
      'subject', jsonb_build_object('type', w.subject_type, 'id', w.subject_id),
      'ref', w.ref,
      'title', coalesce(w.title, "better_supabase"."subject_title"(w.subject_type, w.subject_id)),
      'url', "better_supabase"."subject_url"(w.subject_type, w.subject_id),
      'at', w.at
    ) order by w.at desc nulls last, w.kind, w.ref), '[]'::jsonb)
    from (
      select * from (
    select 'mention'::text, c."subject_type"::text, c."subject_id"::text, m."id"::text, null::text,
      m."sent_at"
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id" and c."kind" = 'subject'
    where v_me = any (m."mentions")
      and m."deleted_at" is null
      and m."sent_at" > now() - interval '30 days'
      and (my_work.tenant is null or m."tenant_id" = my_work.tenant)
    union all
    select 'reminder'::text, d.subject_type, d.subject_id, d.reminder::text, null::text, d.at
    from "better_supabase"."my_reminders_due"(my_work.tenant) d
    where "better_supabase"."can_subject"(d.subject_type, d.subject_id, 'read')
    union all
    select 'approval'::text, r."subject_type"::text, r."subject_id"::text, r."id"::text, null::text,
      r."created_at"
    from "better_supabase"."approval_requests" r
    where r."status" = 'pending'
      and (r."expires_at" is null or r."expires_at" > now())
      and (my_work.tenant is null or r."tenant_id" = my_work.tenant)
      and "better_supabase"."approval_eligible"(r."id")
    union all
    select 'assigned'::text, 'work_item'::text, i."id"::text, i."id"::text, i."title"::text,
      coalesce(i."due_at", a."created_at")
    from "better_supabase"."work_item_assignees" a
    join "better_supabase"."work_items" i on i."id" = a."work_item_id"
    where a."user_id" = v_me
      and i."state" not in ('completed', 'canceled')
      and i."archived_at" is null
      and (my_work.tenant is null or i."tenant_id" = my_work.tenant)
    union all
    select 'assigned'::text, 'maintenance_request'::text, i."id"::text, i."id"::text, i."title"::text,
      coalesce(i."due_at", a."created_at")
    from "better_supabase"."maintenance_request_assignees" a
    join "better_supabase"."maintenance_requests" i on i."id" = a."maintenance_request_id"
    where a."user_id" = v_me
      and i."state" not in ('completed', 'canceled')
      and i."archived_at" is null
      and (my_work.tenant is null or i."tenant_id" = my_work.tenant)
    union all
    select 'sla'::text, k."subject_type"::text, k."subject_id"::text, k."id"::text, null::text,
      k."due_at"
    from "better_supabase"."sla_clocks" k
    where k."subject_type" = 'work_item'
      and k."warned_at" is not null
      and k."met_at" is null
      and (my_work.tenant is null or k."tenant_id" = my_work.tenant)
      and exists (
        select 1 from "better_supabase"."work_item_assignees" a
        where a."work_item_id"::text = k."subject_id"::text
          and a."user_id" = v_me)
    union all
    select 'owned'::text, 'case'::text, c."id"::text, c."number"::text, c."title"::text,
      coalesce(c."due_on"::timestamptz, c."created_at")
    from "better_supabase"."cases" c
    where c."owner_id" = v_me
      and c."status" = 'open'
      and c."archived_at" is null
      and (my_work.tenant is null or c."tenant_id" = my_work.tenant)
      ) u (kind, subject_type, subject_id, ref, title, at)
      order by u.at desc nulls last, u.kind, u.ref
      limit least(greatest(coalesce(my_work.page_size, 50), 1), 200)
    ) w
  );
end;
$$;
revoke execute on function "better_supabase"."my_work"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."my_work"(uuid, integer) to authenticated, service_role;

-- Whether the caller may join presence topic `topic`
-- (presence:<type>:<id>): they can read that subject.
create or replace function "better_supabase"."subject_presence_allowed"(topic text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_parts text[] := regexp_match(subject_presence_allowed.topic, '^presence:([a-z][a-z0-9_-]{0,62}):([^:]{1,200})$');
begin
  if v_parts is null then
    return false;
  end if;
  return coalesce("better_supabase"."can_subject"(v_parts[1], v_parts[2], 'read'), false);
exception
  when invalid_text_representation then
    return false;
end;
$$;
revoke execute on function "better_supabase"."subject_presence_allowed"(text) from public, anon;
grant execute on function "better_supabase"."subject_presence_allowed"(text) to authenticated, service_role;

do $$
begin
  if to_regclass('realtime.messages') is not null then
        drop policy if exists bsb_subject_presence_receive on realtime.messages;
create policy bsb_subject_presence_receive on realtime.messages
  for select to authenticated
  using (realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic())));
        drop policy if exists bsb_subject_presence_send on realtime.messages;
create policy bsb_subject_presence_send on realtime.messages
  for insert to authenticated
  with check ((realtime.messages.extension = 'presence'
        and (select realtime.topic()) like 'presence:' || '%'
        and "better_supabase"."subject_presence_allowed"((select realtime.topic()))) and (select better_supabase.actor_may_write()));
  end if;
end;
$$;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."subject_members";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."subject_members";
create policy bsb_tenant_scope_select on "better_supabase"."subject_members" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or ("team_id" is not null and "team_id" in (select "better_supabase"."team_ids_of"((select auth.uid()))))
    or "tenant_id" in (select better_supabase.tenant_ids_with('subjects.manage'))
    or coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."subject_members";
create policy bsb_tenant_scope_insert on "better_supabase"."subject_members" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."subject_members";
create policy bsb_tenant_scope_update on "better_supabase"."subject_members" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."subject_members";
create policy bsb_tenant_scope_delete on "better_supabase"."subject_members" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.subjects.api: entry points for the Data API.
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

create or replace function "api"."is_subject_member"(subject_type text, subject_id text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."is_subject_member"($1, $2) $$;
revoke execute on function "api"."is_subject_member"(text, text) from public, anon;
grant execute on function "api"."is_subject_member"(text, text) to authenticated, service_role;

create or replace function "api"."has_subject_role"(subject_type text, subject_id text, roles text[])
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."has_subject_role"($1, $2, $3) $$;
revoke execute on function "api"."has_subject_role"(text, text, text[]) from public, anon;
grant execute on function "api"."has_subject_role"(text, text, text[]) to authenticated, service_role;

create or replace function "api"."subject_types"()
returns text[]
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_types"() $$;
revoke execute on function "api"."subject_types"() from public, anon;
grant execute on function "api"."subject_types"() to authenticated, service_role;

create or replace function "api"."subject_title"(subject_type text, subject_id text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_title"($1, $2) $$;
revoke execute on function "api"."subject_title"(text, text) from public, anon;
grant execute on function "api"."subject_title"(text, text) to authenticated, service_role;

create or replace function "api"."subject_url"(subject_type text, subject_id text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_url"($1, $2) $$;
revoke execute on function "api"."subject_url"(text, text) from public, anon;
grant execute on function "api"."subject_url"(text, text) to authenticated, service_role;

create or replace function "api"."subject_titles"(refs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_titles"($1) $$;
revoke execute on function "api"."subject_titles"(jsonb) from public, anon;
grant execute on function "api"."subject_titles"(jsonb) to authenticated, service_role;

create or replace function "api"."can_subject"(subject_type text, subject_id text, action text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can_subject"($1, $2, $3) $$;
revoke execute on function "api"."can_subject"(text, text, text) from public, anon;
grant execute on function "api"."can_subject"(text, text, text) to authenticated, service_role;

create or replace function "api"."record_summary"(subject_type text, subject_id text, sections text[], seen_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_summary"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_summary"(text, text, text[], timestamptz) from public, anon;
grant execute on function "api"."record_summary"(text, text, text[], timestamptz) to authenticated, service_role;

create or replace function "api"."can_subject_for"(member uuid, subject_type text, subject_id text, action text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."can_subject_for"($1, $2, $3, $4) $$;
revoke execute on function "api"."can_subject_for"(uuid, text, text, text) from public, anon, authenticated;
grant execute on function "api"."can_subject_for"(uuid, text, text, text) to service_role;

create or replace function "api"."add_subject_member"(subject_type text, subject_id text, user_id uuid default null, team_id uuid default null, role text default 'member', starts_on date default null, ends_on date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_subject_member"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."add_subject_member"(text, text, uuid, uuid, text, date, date) from public, anon;
grant execute on function "api"."add_subject_member"(text, text, uuid, uuid, text, date, date) to authenticated, service_role;

create or replace function "api"."end_subject_member"(member_id uuid, ends_on date default current_date)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_subject_member"($1, $2) $$;
revoke execute on function "api"."end_subject_member"(uuid, date) from public, anon;
grant execute on function "api"."end_subject_member"(uuid, date) to authenticated, service_role;

create or replace function "api"."list_subject_members"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_subject_members"($1, $2) $$;
revoke execute on function "api"."list_subject_members"(text, text) from public, anon;
grant execute on function "api"."list_subject_members"(text, text) to authenticated, service_role;

create or replace function "api"."my_subjects"(tenant uuid, subject_type text default null, page_size integer default 100, cursor text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_subjects"($1, $2, $3, $4) $$;
revoke execute on function "api"."my_subjects"(uuid, text, integer, text) from public, anon;
grant execute on function "api"."my_subjects"(uuid, text, integer, text) to authenticated, service_role;

create or replace function "api"."record_subject_read"(subject_type text, subject_id text, purpose text default null, block_name text default null, function_name text default null)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_subject_read"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_subject_read"(text, text, text, text, text) from public, anon;
grant execute on function "api"."record_subject_read"(text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."subject_access_log"(subject_type text, subject_id text, since timestamptz default null, max_rows integer default 100)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_access_log"($1, $2, $3, $4) $$;
revoke execute on function "api"."subject_access_log"(text, text, timestamptz, integer) from public, anon;
grant execute on function "api"."subject_access_log"(text, text, timestamptz, integer) to authenticated, service_role;

create or replace function "api"."my_reminders_due"(tenant uuid default null)
returns table (reminder uuid, subject_type text, subject_id text, at timestamptz)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."my_reminders_due"($1) $$;
revoke execute on function "api"."my_reminders_due"(uuid) from public, anon;
grant execute on function "api"."my_reminders_due"(uuid) to authenticated, service_role;

create or replace function "api"."my_work"(tenant uuid default null, page_size integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."my_work"($1, $2) $$;
revoke execute on function "api"."my_work"(uuid, integer) from public, anon;
grant execute on function "api"."my_work"(uuid, integer) to authenticated, service_role;

create or replace function "api"."subject_presence_allowed"(topic text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."subject_presence_allowed"($1) $$;
revoke execute on function "api"."subject_presence_allowed"(text) from public, anon;
grant execute on function "api"."subject_presence_allowed"(text) to authenticated, service_role;

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
