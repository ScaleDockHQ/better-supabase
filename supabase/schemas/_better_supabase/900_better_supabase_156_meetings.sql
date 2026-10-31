-- better-supabase module: meetings
-- @bsb-block meetings@1 managed
-- @bsb-hash sha256:a07565fb8061ab5ceadfc0a9205c1d837e657ab4b00b1f015f69ae0784215827
-- Meetings with an agenda, attendees and roles, minutes per agenda item, decisions the attendees vote on, and action items that become tasks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."meetings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."meetings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meetings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."meetings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meetings";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_attendees";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_attendees";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_attendees";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_attendees";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_attendees";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_agenda_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_agenda_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_agenda_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_agenda_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_agenda_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_decisions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_decisions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_decisions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_decisions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_decisions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_action_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_action_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_action_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_action_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_action_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Meetings per organization: an agenda, attendees, minutes, decisions that
-- members vote on, and action items that become tasks.

create table if not exists "better_supabase"."meetings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- One of options.kinds; the functions check it.
  "kind" text not null check (length("kind") between 1 and 63),
  "title" text not null check (length("title") between 1 and 300),
  "location" text check ("location" is null or length("location") <= 500),
  "starts_at" timestamptz not null,
  "ends_at" timestamptz,
  "status" text not null default 'planned' check ("status" in ('planned', 'in_progress', 'held', 'cancelled')),
  "started_at" timestamptz,
  "held_at" timestamptz,
  "summary" text check ("summary" is null or length("summary") <= 20000),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("ends_at" is null or "ends_at" >= "starts_at")
);
create index if not exists "meetings_tenant_idx" on "better_supabase"."meetings" ("tenant_id", "status", "starts_at" desc);
alter table "better_supabase"."meetings" enable row level security;
revoke all on "better_supabase"."meetings" from public, anon, authenticated;
grant select on "better_supabase"."meetings" to authenticated;
grant all on "better_supabase"."meetings" to service_role;

create table if not exists "better_supabase"."meeting_attendees" (
  "meeting_id" uuid not null,
  "tenant_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null default 'attendee' check ("role" in ('chair', 'secretary', 'attendee', 'guest')),
  "attendance" text not null default 'invited' check ("attendance" in ('invited', 'present', 'absent', 'excused')),
  "created_at" timestamptz not null default now(),
  primary key ("meeting_id", "user_id"),
  foreign key ("tenant_id", "meeting_id") references "better_supabase"."meetings" ("tenant_id", "id") on delete cascade
);
create index if not exists "meeting_attendees_parent_idx" on "better_supabase"."meeting_attendees" ("tenant_id", "meeting_id");
create index if not exists "meeting_attendees_user_idx" on "better_supabase"."meeting_attendees" ("user_id", "meeting_id");
-- One chair per meeting.
create unique index if not exists "meeting_attendees_chair_key" on "better_supabase"."meeting_attendees" ("meeting_id") where "role" = 'chair';
alter table "better_supabase"."meeting_attendees" enable row level security;
revoke all on "better_supabase"."meeting_attendees" from public, anon, authenticated;
grant select on "better_supabase"."meeting_attendees" to authenticated;
grant all on "better_supabase"."meeting_attendees" to service_role;

-- The caller's role at a meeting, or null. Definer, so the read policies can
-- ask it without reading the attendees table through its own policy.
create or replace function "better_supabase"."meeting_role"(meeting_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."role" from "better_supabase"."meeting_attendees" x
  where x."meeting_id" = meeting_role.meeting_id and x."user_id" = auth.uid();
$$;
revoke execute on function "better_supabase"."meeting_role"(uuid) from public, anon;
grant execute on function "better_supabase"."meeting_role"(uuid) to authenticated, service_role;
drop policy if exists meetings_read on "better_supabase"."meetings";
create policy meetings_read on "better_supabase"."meetings"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("id") is not null);
drop policy if exists meeting_attendees_read on "better_supabase"."meeting_attendees";
create policy meeting_attendees_read on "better_supabase"."meeting_attendees"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null);

create table if not exists "better_supabase"."meeting_agenda_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "meeting_id" uuid not null,
  "ordinal" integer not null check ("ordinal" > 0),
  "title" text not null check (length("title") between 1 and 300),
  "notes" text check ("notes" is null or length("notes") <= 10000),
  "presenter_id" uuid,
  -- Minutes of this item, in Markdown.
  "minutes" text check ("minutes" is null or length("minutes") <= 50000),
  "status" text not null default 'open' check ("status" in ('open', 'covered', 'skipped')),
  "outcome" text check ("outcome" is null or length("outcome") <= 2000),
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  unique ("meeting_id", "ordinal") deferrable initially deferred,
  foreign key ("tenant_id", "meeting_id") references "better_supabase"."meetings" ("tenant_id", "id") on delete cascade
);
create index if not exists "meeting_agenda_items_parent_idx" on "better_supabase"."meeting_agenda_items" ("tenant_id", "meeting_id", "ordinal");
alter table "better_supabase"."meeting_agenda_items" enable row level security;
revoke all on "better_supabase"."meeting_agenda_items" from public, anon, authenticated;
grant select on "better_supabase"."meeting_agenda_items" to authenticated;
grant all on "better_supabase"."meeting_agenda_items" to service_role;
drop policy if exists meeting_agenda_items_read on "better_supabase"."meeting_agenda_items";
create policy meeting_agenda_items_read on "better_supabase"."meeting_agenda_items"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null);

create table if not exists "better_supabase"."meeting_decisions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "meeting_id" uuid not null,
  "agenda_item_id" uuid,
  "title" text not null check (length("title") between 1 and 300),
  "body" text check ("body" is null or length("body") <= 10000),
  "status" text not null default 'proposed' check ("status" in ('proposed', 'passed', 'rejected', 'deferred')),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "meeting_id") references "better_supabase"."meetings" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "agenda_item_id") references "better_supabase"."meeting_agenda_items" ("tenant_id", "id") on delete set null ("agenda_item_id")
);
create index if not exists "meeting_decisions_parent_idx" on "better_supabase"."meeting_decisions" ("tenant_id", "meeting_id");
create index if not exists "meeting_decisions_agenda_idx" on "better_supabase"."meeting_decisions" ("tenant_id", "agenda_item_id");
alter table "better_supabase"."meeting_decisions" enable row level security;
revoke all on "better_supabase"."meeting_decisions" from public, anon, authenticated;
grant select on "better_supabase"."meeting_decisions" to authenticated;
grant all on "better_supabase"."meeting_decisions" to service_role;
drop policy if exists meeting_decisions_read on "better_supabase"."meeting_decisions";
create policy meeting_decisions_read on "better_supabase"."meeting_decisions"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null);

-- The tasks opened from a meeting. The work item stays in the tasks block;
-- this row only says where it came from.
create table if not exists "better_supabase"."meeting_action_items" (
  "task_id" uuid primary key references "better_supabase"."work_items" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "meeting_id" uuid not null,
  "agenda_item_id" uuid,
  "decision_id" uuid,
  "created_at" timestamptz not null default now(),
  foreign key ("tenant_id", "meeting_id") references "better_supabase"."meetings" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "agenda_item_id") references "better_supabase"."meeting_agenda_items" ("tenant_id", "id") on delete set null ("agenda_item_id"),
  foreign key ("tenant_id", "decision_id") references "better_supabase"."meeting_decisions" ("tenant_id", "id") on delete set null ("decision_id")
);
create index if not exists "meeting_action_items_parent_idx" on "better_supabase"."meeting_action_items" ("tenant_id", "meeting_id");
create index if not exists "meeting_action_items_agenda_idx" on "better_supabase"."meeting_action_items" ("tenant_id", "agenda_item_id");
create index if not exists "meeting_action_items_decision_idx" on "better_supabase"."meeting_action_items" ("tenant_id", "decision_id");
alter table "better_supabase"."meeting_action_items" enable row level security;
revoke all on "better_supabase"."meeting_action_items" from public, anon, authenticated;
grant select on "better_supabase"."meeting_action_items" to authenticated;
grant all on "better_supabase"."meeting_action_items" to service_role;
drop policy if exists meeting_action_items_read on "better_supabase"."meeting_action_items";
create policy meeting_action_items_read on "better_supabase"."meeting_action_items"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null);


-- Replaces the attendees of a meeting with team, [{ userId, role, attendance }].
-- Every attendee belongs to the organization and one at most chairs. The other
-- functions call it; it is not an entry point.
create or replace function "better_supabase"."meeting_set_attendees"(meeting_id uuid, tenant uuid, team jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_team jsonb := coalesce(meeting_set_attendees.team, '[]'::jsonb);
begin
  if jsonb_typeof(v_team) is distinct from 'array' then
    raise exception 'attendees must be a list' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where jsonb_typeof(e) <> 'object' or coalesce(e ->> 'userId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      or coalesce(e ->> 'role', 'attendee') not in ('chair', 'secretary', 'attendee', 'guest')
      or coalesce(e ->> 'attendance', 'invited') not in ('invited', 'present', 'absent', 'excused')
  ) then
    raise exception 'each attendee needs a userId, a role of chair, secretary, attendee or guest, and an attendance of invited, present, absent or excused' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if (select count(distinct e ->> 'userId') from jsonb_array_elements(v_team) e) <> jsonb_array_length(v_team) then
    raise exception 'a user is listed twice' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if (select count(*) from jsonb_array_elements(v_team) e where e ->> 'role' = 'chair') > 1 then
    raise exception 'a meeting has one chair' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_team) e
    where not exists (
      select 1 from "public"."memberships" y
      where y."organization_id" = meeting_set_attendees.tenant
        and y."user_id" = (e ->> 'userId')::uuid
    )
  ) then
    raise exception 'every attendee must belong to the organization' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  delete from "better_supabase"."meeting_attendees" x where x."meeting_id" = meeting_set_attendees.meeting_id;
  insert into "better_supabase"."meeting_attendees" ("meeting_id", "tenant_id", "user_id", "role", "attendance")
  select meeting_set_attendees.meeting_id, meeting_set_attendees.tenant, (e ->> 'userId')::uuid,
    coalesce(e ->> 'role', 'attendee'), coalesce(e ->> 'attendance', 'invited')
  from jsonb_array_elements(v_team) e;
end;
$$;
revoke execute on function "better_supabase"."meeting_set_attendees"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."meeting_set_attendees"(uuid, uuid, jsonb) to service_role;

-- Plans a meeting. input is { kind, title, location, startsAt, endsAt,
-- attendees: [{ userId, role, attendance }], agenda: [{ title, notes,
-- presenterId }] }. It starts planned. Needs meetings.write.
create or replace function "better_supabase"."create_meeting"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_kind text;
  v_title text;
  v_starts timestamptz;
  v_ends timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_meeting.tenant is not null and coalesce(better_supabase.can('tenant', create_meeting.tenant, 'meetings.write'), false))) then
    raise exception 'not allowed to plan meetings' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_meeting.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  begin
    v_kind := coalesce(nullif(trim(create_meeting.input ->> 'kind'), ''), (array['meeting', 'board', 'management_review', 'one_on_one', 'toolbox_talk']::text[])[1]);
    v_title := trim(create_meeting.input ->> 'title');
    v_starts := (create_meeting.input ->> 'startsAt')::timestamptz;
    v_ends := (create_meeting.input ->> 'endsAt')::timestamptz;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'startsAt and endsAt are timestamps' using errcode = '22023', hint = 'MEETING_INVALID';
  end;
  if v_kind is null or not (v_kind = any (array['meeting', 'board', 'management_review', 'one_on_one', 'toolbox_talk']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'MEETING_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a meeting needs a title of 1 to 300 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'a meeting needs a start time' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_ends < v_starts then
    raise exception 'endsAt is on or after startsAt' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(create_meeting.input ->> 'location') > 500 then
    raise exception 'location is at most 500 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(create_meeting.input ->> 'summary') > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if create_meeting.input ? 'agenda' and jsonb_typeof(create_meeting.input -> 'agenda') is distinct from 'array' then
    raise exception 'agenda must be a list' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_meeting_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_meeting.tenant, create_meeting.input;
    end if;
  end;
  insert into "better_supabase"."meetings" ("tenant_id", "kind", "title", "starts_at", "ends_at", "location", "summary", "created_by")
  values (create_meeting.tenant, v_kind, v_title, v_starts, v_ends, nullif(trim(create_meeting.input ->> 'location'), ''), nullif(trim(create_meeting.input ->> 'summary'), ''), auth.uid())
  returning * into v_row;
  perform "better_supabase"."meeting_set_attendees"(v_row."id", v_row."tenant_id", create_meeting.input -> 'attendees');
  insert into "better_supabase"."meeting_agenda_items" ("tenant_id", "meeting_id", "ordinal", "title", "notes", "presenter_id")
  select v_row."tenant_id", v_row."id", e.n, trim(e.value ->> 'title'), nullif(trim(e.value ->> 'notes'), ''), nullif(e.value ->> 'presenterId', '')::uuid
  from jsonb_array_elements(coalesce(create_meeting.input -> 'agenda', '[]'::jsonb)) with ordinality as e(value, n);
  perform "better_supabase".emit_event('meeting.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.created',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting planned',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_meeting_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when check_violation or invalid_text_representation or not_null_violation then
  raise exception 'an attendee or an agenda item has an invalid value' using errcode = '22023', hint = 'MEETING_INVALID';
end;
$$;
revoke execute on function "better_supabase"."create_meeting"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_meeting"(uuid, jsonb) to authenticated, service_role;

-- Changes a meeting: the keys of create_meeting except attendees and agenda,
-- and summary. A cancelled meeting takes no changes. Needs meetings.manage, or
-- meetings.write as its creator, chair or secretary.
create or replace function "better_supabase"."update_meeting"(meeting_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_kind text;
  v_title text;
  v_starts timestamptz;
  v_ends timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = update_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'a cancelled meeting takes no changes' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if jsonb_typeof(update_meeting.changes) is distinct from 'object' then
    raise exception 'changes must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  begin
    v_kind := coalesce(nullif(trim(update_meeting.changes ->> 'kind'), ''), v_row."kind");
    v_title := case when update_meeting.changes ? 'title' then trim(update_meeting.changes ->> 'title') else v_row."title" end;
    v_starts := case when update_meeting.changes ? 'startsAt' then (update_meeting.changes ->> 'startsAt')::timestamptz else v_row."starts_at" end;
    v_ends := case when update_meeting.changes ? 'endsAt' then (update_meeting.changes ->> 'endsAt')::timestamptz else v_row."ends_at" end;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'startsAt and endsAt are timestamps' using errcode = '22023', hint = 'MEETING_INVALID';
  end;
  if v_kind is null or not (v_kind = any (array['meeting', 'board', 'management_review', 'one_on_one', 'toolbox_talk']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'MEETING_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a meeting needs a title of 1 to 300 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'a meeting needs a start time' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_ends < v_starts then
    raise exception 'endsAt is on or after startsAt' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(update_meeting.changes ->> 'location') > 500 then
    raise exception 'location is at most 500 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(update_meeting.changes ->> 'summary') > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  update "better_supabase"."meetings" x set
    "kind" = v_kind,
    "title" = v_title,
    "location" = case when update_meeting.changes ? 'location' then nullif(trim(update_meeting.changes ->> 'location'), '') else x."location" end,
    "summary" = case when update_meeting.changes ? 'summary' then nullif(trim(update_meeting.changes ->> 'summary'), '') else x."summary" end,
    "starts_at" = v_starts,
    "ends_at" = v_ends,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.updated',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting updated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."update_meeting"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_meeting"(uuid, jsonb) to authenticated, service_role;

-- Opens a planned meeting.
create or replace function "better_supabase"."start_meeting"(meeting_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = start_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to start this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" <> 'planned' then
    raise exception 'the meeting can''t move from % to %', v_row."status", 'in_progress' using errcode = '55000', hint = 'MEETING_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'in_progress')::text;
  end if;
  update "better_supabase"."meetings" x set "status" = 'in_progress', "started_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.started', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.started',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting started',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."start_meeting"(uuid) from public, anon;
grant execute on function "better_supabase"."start_meeting"(uuid) to authenticated, service_role;

-- Closes a meeting as held, with an optional summary. Every proposed
-- decision stays proposed until someone decides it.
create or replace function "better_supabase"."hold_meeting"(meeting_id uuid, summary text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = hold_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to close this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" not in ('planned', 'in_progress') then
    raise exception 'the meeting can''t move from % to %', v_row."status", 'held' using errcode = '55000', hint = 'MEETING_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'held')::text;
  end if;
  if length(hold_meeting.summary) > 20000 then
    raise exception 'summary is at most 20000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_meeting_hold"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."meetings" x set
    "status" = 'held',
    "started_at" = coalesce(x."started_at", now()),
    "held_at" = now(),
    "summary" = coalesce(nullif(trim(hold_meeting.summary), ''), x."summary"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.concluded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.concluded',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting held',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_meeting_hold"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."hold_meeting"(uuid, text) from public, anon;
grant execute on function "better_supabase"."hold_meeting"(uuid, text) to authenticated, service_role;

-- Cancels a meeting that was not held.
create or replace function "better_supabase"."cancel_meeting"(meeting_id uuid, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = cancel_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to cancel this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" in ('held', 'cancelled') then
    raise exception 'the meeting can''t move from % to %', v_row."status", 'cancelled' using errcode = '55000', hint = 'MEETING_STATUS_INVALID', detail = jsonb_build_object('from', v_row."status", 'to', 'cancelled')::text;
  end if;
  if length(cancel_meeting.reason) > 4000 then
    raise exception 'reason is at most 4000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  update "better_supabase"."meetings" x set "status" = 'cancelled', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('meeting.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_meeting.reason), '')), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.cancelled',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting cancelled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status", 'reason', nullif(trim(cancel_meeting.reason), ''))
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_meeting"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_meeting"(uuid, text) to authenticated, service_role;

-- Deletes a meeting that is planned or cancelled, with its agenda and
-- decisions. Tasks opened from it stay in the tasks block.
create or replace function "better_supabase"."delete_meeting"(meeting_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = delete_meeting.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to delete this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" not in ('planned', 'cancelled') then
    raise exception 'only a planned or cancelled meeting can be deleted' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  delete from "better_supabase"."meetings" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('meeting.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting.deleted',
    category => 'data',
    target_type => 'meeting',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'meeting deleted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_meeting"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_meeting"(uuid) to authenticated, service_role;

-- Invites a user to a meeting, or changes their role or attendance. A new
-- chair replaces the old one, who becomes an attendee.
create or replace function "better_supabase"."set_meeting_attendee"(meeting_id uuid, user_id uuid, role text default 'attendee', attendance text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_attendee "better_supabase"."meeting_attendees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = set_meeting_attendee.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change who attends this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'a cancelled meeting takes no changes' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if set_meeting_attendee.role not in ('chair', 'secretary', 'attendee', 'guest')
    or set_meeting_attendee.attendance not in ('invited', 'present', 'absent', 'excused') then
    raise exception 'role or attendance is not one of the allowed values' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if not exists (
    select 1 from "public"."memberships" y
    where y."organization_id" = v_row."tenant_id" and y."user_id" = set_meeting_attendee.user_id
  ) then
    raise exception 'the attendee must belong to the organization' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if set_meeting_attendee.role = 'chair' then
    update "better_supabase"."meeting_attendees" x set "role" = 'attendee'
    where x."meeting_id" = v_row."id" and x."role" = 'chair' and x."user_id" <> set_meeting_attendee.user_id;
  end if;
  update "better_supabase"."meeting_attendees" x set
    "role" = set_meeting_attendee.role,
    "attendance" = coalesce(set_meeting_attendee.attendance, x."attendance")
  where x."meeting_id" = v_row."id" and x."user_id" = set_meeting_attendee.user_id
  returning * into v_attendee;
  if not found then
    insert into "better_supabase"."meeting_attendees" ("meeting_id", "tenant_id", "user_id", "role", "attendance")
    values (v_row."id", v_row."tenant_id", set_meeting_attendee.user_id, set_meeting_attendee.role, coalesce(set_meeting_attendee.attendance, 'invited'))
    returning * into v_attendee;
  end if;
  return jsonb_build_object('meetingId', v_attendee."meeting_id", 'userId', v_attendee."user_id", 'role', v_attendee."role", 'attendance', v_attendee."attendance");
end;
$$;
revoke execute on function "better_supabase"."set_meeting_attendee"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_meeting_attendee"(uuid, uuid, text, text) to authenticated, service_role;

-- Removes a user from a meeting.
create or replace function "better_supabase"."remove_meeting_attendee"(meeting_id uuid, user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_attendee "better_supabase"."meeting_attendees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = remove_meeting_attendee.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change who attends this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  delete from "better_supabase"."meeting_attendees" x
  where x."meeting_id" = v_row."id" and x."user_id" = remove_meeting_attendee.user_id
  returning * into v_attendee;
  if not found then
    raise exception 'that user is not an attendee' using errcode = 'P0002', hint = 'MEETING_ATTENDEE_NOT_FOUND';
  end if;
  return jsonb_build_object('meetingId', v_attendee."meeting_id", 'userId', v_attendee."user_id", 'role', v_attendee."role", 'attendance', v_attendee."attendance");
end;
$$;
revoke execute on function "better_supabase"."remove_meeting_attendee"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_meeting_attendee"(uuid, uuid) to authenticated, service_role;

-- Adds an agenda item, or with item.id changes one. item is { id, title,
-- notes, presenterId, minutes, status, outcome, ordinal }. Without an ordinal
-- a new item goes last; with one, the items from there move down.
create or replace function "better_supabase"."save_meeting_agenda_item"(meeting_id uuid, item jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_item "better_supabase"."meeting_agenda_items";
  v_id uuid;
  v_ordinal integer;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = save_meeting_agenda_item.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change this agenda' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'a cancelled meeting takes no changes' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if jsonb_typeof(save_meeting_agenda_item.item) is distinct from 'object' then
    raise exception 'item must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  begin
    v_id := nullif(save_meeting_agenda_item.item ->> 'id', '')::uuid;
    v_ordinal := (save_meeting_agenda_item.item ->> 'ordinal')::integer;
  exception when invalid_text_representation then
    raise exception 'id is a uuid and ordinal an integer' using errcode = '22023', hint = 'MEETING_INVALID';
  end;
  v_status := save_meeting_agenda_item.item ->> 'status';
  if v_status is not null and v_status not in ('open', 'covered', 'skipped') then
    raise exception 'status is open, covered or skipped' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_ordinal is not null and v_ordinal < 1 then
    raise exception 'ordinal starts at 1' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(save_meeting_agenda_item.item ->> 'minutes') > 50000 then
    raise exception 'minutes is at most 50000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_id is null then
    if coalesce(length(trim(save_meeting_agenda_item.item ->> 'title')), 0) not between 1 and 300 then
      raise exception 'an agenda item needs a title of 1 to 300 characters' using errcode = '22023', hint = 'MEETING_INVALID';
    end if;
    v_ordinal := coalesce(v_ordinal, (select coalesce(max(y."ordinal"), 0) + 1 from "better_supabase"."meeting_agenda_items" y where y."meeting_id" = v_row."id"));
    update "better_supabase"."meeting_agenda_items" y set "ordinal" = y."ordinal" + 1
    where y."meeting_id" = v_row."id" and y."ordinal" >= v_ordinal;
    insert into "better_supabase"."meeting_agenda_items" ("tenant_id", "meeting_id", "ordinal", "title", "notes", "presenter_id", "minutes", "status", "outcome")
    values (v_row."tenant_id", v_row."id", v_ordinal, trim(save_meeting_agenda_item.item ->> 'title'), nullif(trim(save_meeting_agenda_item.item ->> 'notes'), ''),
      nullif(save_meeting_agenda_item.item ->> 'presenterId', '')::uuid, nullif(save_meeting_agenda_item.item ->> 'minutes', ''), coalesce(v_status, 'open'), nullif(trim(save_meeting_agenda_item.item ->> 'outcome'), ''))
    returning * into v_item;
  else
    select * into v_item from "better_supabase"."meeting_agenda_items" y where y."id" = v_id and y."meeting_id" = v_row."id" for update;
    if not found then
      raise exception 'no such agenda item' using errcode = 'P0002', hint = 'MEETING_AGENDA_ITEM_NOT_FOUND';
    end if;
    if v_ordinal is not null and v_ordinal <> v_item."ordinal" then
      update "better_supabase"."meeting_agenda_items" y set "ordinal" = y."ordinal" + 1
      where y."meeting_id" = v_row."id" and y."ordinal" >= v_ordinal and y."id" <> v_item."id";
    end if;
    update "better_supabase"."meeting_agenda_items" y set
      "ordinal" = coalesce(v_ordinal, y."ordinal"),
      "title" = case when save_meeting_agenda_item.item ? 'title' then trim(save_meeting_agenda_item.item ->> 'title') else y."title" end,
      "notes" = case when save_meeting_agenda_item.item ? 'notes' then nullif(trim(save_meeting_agenda_item.item ->> 'notes'), '') else y."notes" end,
      "presenter_id" = case when save_meeting_agenda_item.item ? 'presenterId' then nullif(save_meeting_agenda_item.item ->> 'presenterId', '')::uuid else y."presenter_id" end,
      "minutes" = case when save_meeting_agenda_item.item ? 'minutes' then nullif(save_meeting_agenda_item.item ->> 'minutes', '') else y."minutes" end,
      "status" = coalesce(v_status, y."status"),
      "outcome" = case when save_meeting_agenda_item.item ? 'outcome' then nullif(trim(save_meeting_agenda_item.item ->> 'outcome'), '') else y."outcome" end
    where y."id" = v_item."id"
    returning * into v_item;
  end if;
  if coalesce(length(v_item."title"), 0) not between 1 and 300 then
    raise exception 'an agenda item needs a title of 1 to 300 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  update "better_supabase"."meetings" x set "updated_at" = now() where x."id" = v_row."id";
  return jsonb_build_object('id', v_item."id", 'meetingId', v_item."meeting_id", 'ordinal', v_item."ordinal", 'title', v_item."title", 'notes', v_item."notes", 'presenterId', v_item."presenter_id", 'minutes', v_item."minutes", 'status', v_item."status", 'outcome', v_item."outcome");
end;
$$;
revoke execute on function "better_supabase"."save_meeting_agenda_item"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_meeting_agenda_item"(uuid, jsonb) to authenticated, service_role;

-- Removes an agenda item and closes the gap in the numbering. Decisions and
-- tasks that named it keep existing without it.
create or replace function "better_supabase"."delete_meeting_agenda_item"(item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_item "better_supabase"."meeting_agenda_items";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_item from "better_supabase"."meeting_agenda_items" y where y."id" = delete_meeting_agenda_item.item_id;
  if not found then
    raise exception 'no such agenda item' using errcode = 'P0002', hint = 'MEETING_AGENDA_ITEM_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = v_item."meeting_id" for update;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to change this agenda' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  delete from "better_supabase"."meeting_agenda_items" y where y."id" = v_item."id";
  update "better_supabase"."meeting_agenda_items" y set "ordinal" = z.n
  from (
    select s."id" as id, row_number() over (order by s."ordinal") as n
    from "better_supabase"."meeting_agenda_items" s where s."meeting_id" = v_row."id"
  ) z
  where y."id" = z.id and y."ordinal" <> z.n;
  return jsonb_build_object('id', v_item."id", 'meetingId', v_item."meeting_id", 'ordinal', v_item."ordinal", 'title', v_item."title", 'notes', v_item."notes", 'presenterId', v_item."presenter_id", 'minutes', v_item."minutes", 'status', v_item."status", 'outcome', v_item."outcome");
end;
$$;
revoke execute on function "better_supabase"."delete_meeting_agenda_item"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_meeting_agenda_item"(uuid) to authenticated, service_role;

-- Records a decision of a meeting. input is { title, body, agendaItemId,
-- status }. It starts proposed, and the attendees vote on it through the
-- reactions block (subject type meeting_decision) until someone decides it.
create or replace function "better_supabase"."record_meeting_decision"(meeting_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_decision "better_supabase"."meeting_decisions";
  v_status text;
  v_agenda uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = record_meeting_decision.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to record decisions for this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_row."status" = 'cancelled' then
    raise exception 'a cancelled meeting takes no decisions' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if jsonb_typeof(record_meeting_decision.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if coalesce(length(trim(record_meeting_decision.input ->> 'title')), 0) not between 1 and 300 then
    raise exception 'a decision needs a title of 1 to 300 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  v_status := coalesce(record_meeting_decision.input ->> 'status', 'proposed');
  if v_status not in ('proposed', 'passed', 'rejected', 'deferred') then
    raise exception 'status is proposed, passed, rejected or deferred' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if length(record_meeting_decision.input ->> 'body') > 10000 then
    raise exception 'body is at most 10000 characters' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  begin
    v_agenda := nullif(record_meeting_decision.input ->> 'agendaItemId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'agendaItemId is a uuid' using errcode = '22023', hint = 'MEETING_INVALID';
  end;
  if v_agenda is not null and not exists (
    select 1 from "better_supabase"."meeting_agenda_items" y where y."id" = v_agenda and y."meeting_id" = v_row."id"
  ) then
    raise exception 'the agenda item belongs to another meeting' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  insert into "better_supabase"."meeting_decisions" ("tenant_id", "meeting_id", "agenda_item_id", "title", "body", "status", "decided_by", "decided_at")
  values (v_row."tenant_id", v_row."id", v_agenda, trim(record_meeting_decision.input ->> 'title'), nullif(trim(record_meeting_decision.input ->> 'body'), ''), v_status,
    case when v_status = 'proposed' then null else auth.uid() end, case when v_status = 'proposed' then null else now() end)
  returning * into v_decision;
  perform "better_supabase".emit_event('meeting_decision.recorded', jsonb_build_object('organizationId', v_decision."tenant_id", 'id', v_decision."id", 'meetingId', v_decision."meeting_id", 'title', v_decision."title", 'status', v_decision."status"), 'meeting-decisions/' || v_decision."id"::text, (v_decision."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting_decision.recorded',
    category => 'data',
    target_type => 'meeting_decision',
    record_id => v_decision."id"::text,
    target_label => v_decision."title",
    tenant => (v_decision."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_decision."tenant_id", 'id', v_decision."id", 'meetingId', v_decision."meeting_id", 'title', v_decision."title", 'status', v_decision."status")
  );
  return jsonb_build_object('id', v_decision."id", 'organizationId', v_decision."tenant_id", 'meetingId', v_decision."meeting_id", 'agendaItemId', v_decision."agenda_item_id", 'title', v_decision."title", 'body', v_decision."body", 'status', v_decision."status", 'decidedBy', v_decision."decided_by", 'decidedAt', v_decision."decided_at", 'createdAt', v_decision."created_at");
end;
$$;
revoke execute on function "better_supabase"."record_meeting_decision"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."record_meeting_decision"(uuid, jsonb) to authenticated, service_role;

-- Decides a decision as passed, rejected or deferred. Without status it
-- follows the votes: more up than down passes, more down than up rejects, a
-- tie defers. That needs the reactions block.
create or replace function "better_supabase"."decide_meeting_decision"(decision_id uuid, status text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_decision "better_supabase"."meeting_decisions";
  v_votes jsonb;
  v_status text := decide_meeting_decision.status;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_decision from "better_supabase"."meeting_decisions" y where y."id" = decide_meeting_decision.decision_id for update;
  if not found then
    raise exception 'no such decision' using errcode = 'P0002', hint = 'MEETING_DECISION_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = v_decision."meeting_id";
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to decide for this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_status is not null and v_status not in ('passed', 'rejected', 'deferred') then
    raise exception 'status is passed, rejected or deferred' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_status is null then
    v_votes := "better_supabase"."vote_tally"(v_decision."tenant_id", 'meeting_decision', v_decision."id"::text);
    if v_votes is null then
      raise exception 'without the reactions block a decision needs a status' using errcode = '22023', hint = 'MEETING_INVALID';
    end if;
    v_status := case
      when (v_votes ->> 'up')::integer > (v_votes ->> 'down')::integer then 'passed'
      when (v_votes ->> 'down')::integer > (v_votes ->> 'up')::integer then 'rejected'
      else 'deferred' end;
  end if;
  update "better_supabase"."meeting_decisions" y set "status" = v_status, "decided_by" = auth.uid(), "decided_at" = now()
  where y."id" = v_decision."id"
  returning * into v_decision;
  perform "better_supabase".emit_event('meeting_decision.decided', jsonb_build_object('organizationId', v_decision."tenant_id", 'id', v_decision."id", 'meetingId', v_decision."meeting_id", 'title', v_decision."title", 'status', v_decision."status"), 'meeting-decisions/' || v_decision."id"::text, (v_decision."tenant_id")::text, null, 'better-supabase/meetings');
  perform better_supabase.audit_event(
    event_type => 'meeting_decision.decided',
    category => 'data',
    target_type => 'meeting_decision',
    record_id => v_decision."id"::text,
    target_label => v_decision."title",
    tenant => (v_decision."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_decision."tenant_id", 'id', v_decision."id", 'meetingId', v_decision."meeting_id", 'title', v_decision."title", 'status', v_decision."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_meeting_decision"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_decision."id";
    end if;
  end;
  return jsonb_build_object('id', v_decision."id", 'organizationId', v_decision."tenant_id", 'meetingId', v_decision."meeting_id", 'agendaItemId', v_decision."agenda_item_id", 'title', v_decision."title", 'body', v_decision."body", 'status', v_decision."status", 'decidedBy', v_decision."decided_by", 'decidedAt', v_decision."decided_at", 'createdAt', v_decision."created_at");
end;
$$;
revoke execute on function "better_supabase"."decide_meeting_decision"(uuid, text) from public, anon;
grant execute on function "better_supabase"."decide_meeting_decision"(uuid, text) to authenticated, service_role;

-- Opens a task from a meeting. task and assignees are what create_task takes;
-- the task keeps living in the tasks block, and this only records where it
-- came from, with the agenda item and the decision it follows from.
create or replace function "better_supabase"."add_meeting_action_item"(meeting_id uuid, task jsonb, assignees uuid[] default '{}', agenda_item_id uuid default null, decision_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
  v_task jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = add_meeting_action_item.meeting_id for update;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.manage'), false))) or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.write'), false) and (coalesce(v_row."created_by" = auth.uid(), false) or coalesce("better_supabase"."meeting_role"(v_row."id") in ('chair', 'secretary'), false)))) then
    raise exception 'not allowed to add action items to this meeting' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if add_meeting_action_item.agenda_item_id is not null and not exists (
    select 1 from "better_supabase"."meeting_agenda_items" y where y."id" = add_meeting_action_item.agenda_item_id and y."meeting_id" = v_row."id"
  ) then
    raise exception 'the agenda item belongs to another meeting' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if add_meeting_action_item.decision_id is not null and not exists (
    select 1 from "better_supabase"."meeting_decisions" y where y."id" = add_meeting_action_item.decision_id and y."meeting_id" = v_row."id"
  ) then
    raise exception 'the decision belongs to another meeting' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  v_task := "better_supabase"."create_work_item"(v_row."tenant_id", add_meeting_action_item.task, coalesce(add_meeting_action_item.assignees, '{}'));
  insert into "better_supabase"."meeting_action_items" ("task_id", "tenant_id", "meeting_id", "agenda_item_id", "decision_id")
  values ((v_task ->> 'id')::uuid, v_row."tenant_id", v_row."id", add_meeting_action_item.agenda_item_id, add_meeting_action_item.decision_id);
  perform "better_supabase".emit_event('meeting_action_item.created', jsonb_build_object('organizationId', v_row."tenant_id", 'meetingId', v_row."id", 'workItemId', (v_task ->> 'id')::uuid, 'title', v_task ->> 'title'), 'meetings/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/meetings');
  return v_task || jsonb_build_object('meetingId', v_row."id", 'agendaItemId', add_meeting_action_item.agenda_item_id, 'decisionId', add_meeting_action_item.decision_id);
end;
$$;
revoke execute on function "better_supabase"."add_meeting_action_item"(uuid, jsonb, uuid[], uuid, uuid) from public, anon;
grant execute on function "better_supabase"."add_meeting_action_item"(uuid, jsonb, uuid[], uuid, uuid) to authenticated, service_role;


-- A meeting with its attendees, agenda, decisions (with their vote tally when
-- the reactions block is there) and the tasks opened from it. Readers of
-- meetings and the meeting's attendees see it.
create or replace function "better_supabase"."get_meeting"(meeting_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."meetings";
begin
  select * into v_row from "better_supabase"."meetings" x where x."id" = get_meeting.meeting_id;
  if not found or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'meetings.read'), false))) or "better_supabase"."meeting_role"(v_row."id") is not null) then
    raise exception 'no such meeting' using errcode = 'P0002', hint = 'MEETING_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'title', v_row."title", 'location', v_row."location", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'status', v_row."status", 'startedAt', v_row."started_at", 'heldAt', v_row."held_at", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'attendees', coalesce((
      select jsonb_agg(jsonb_build_object('meetingId', y."meeting_id", 'userId', y."user_id", 'role', y."role", 'attendance', y."attendance")
        order by case y."role" when 'chair' then 0 when 'secretary' then 1 when 'attendee' then 2 else 3 end, y."created_at")
      from "better_supabase"."meeting_attendees" y where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb),
    'agenda', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'meetingId', y."meeting_id", 'ordinal', y."ordinal", 'title', y."title", 'notes', y."notes", 'presenterId', y."presenter_id", 'minutes', y."minutes", 'status', y."status", 'outcome', y."outcome") order by y."ordinal")
      from "better_supabase"."meeting_agenda_items" y where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'meetingId', y."meeting_id", 'agendaItemId', y."agenda_item_id", 'title', y."title", 'body', y."body", 'status', y."status", 'decidedBy', y."decided_by", 'decidedAt', y."decided_at", 'createdAt', y."created_at") || jsonb_build_object('votes', "better_supabase"."vote_tally"(y."tenant_id", 'meeting_decision', y."id"::text)) order by y."created_at")
      from "better_supabase"."meeting_decisions" y where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb),
    'actionItems', coalesce((
      select jsonb_agg(jsonb_build_object('workItemId', z."id", 'title', z."title", 'state', z."state", 'dueAt', z."due_at",
        'agendaItemId', y."agenda_item_id", 'decisionId', y."decision_id") order by y."created_at")
      from "better_supabase"."meeting_action_items" y join "better_supabase"."work_items" z on z."id" = y."task_id"
      where y."tenant_id" = v_row."tenant_id" and y."meeting_id" = v_row."id"
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."get_meeting"(uuid) from public, anon;
grant execute on function "better_supabase"."get_meeting"(uuid) to authenticated, service_role;

-- The organization's meetings, the latest first. filters is { kind, status,
-- from, to (on the start time), attendeeId, search, limit, offset }. Without
-- meetings.read the caller sees only the meetings they attend.
create or replace function "better_supabase"."list_meetings"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_meetings.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_meetings.tenant is not null and coalesce(better_supabase.can('tenant', list_meetings.tenant, 'meetings.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read meetings' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."starts_at" desc, x."id")
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'from' or x."starts_at" >= (v_filters ->> 'from')::timestamptz)
        and (not v_filters ? 'to' or x."starts_at" <= (v_filters ->> 'to')::timestamptz)
        and (not v_filters ? 'attendeeId' or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = (v_filters ->> 'attendeeId')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
      order by x."starts_at" desc, x."id"
      limit v_limit offset v_offset
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_meetings"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_meetings"(uuid, jsonb) to authenticated, service_role;


-- Mirrors a planned or running meeting to an event in the calendar Meetings:
-- one event per meeting, uid meeting-<id>. It skips the organization's missing
-- calendar and removes the event once the meeting is held or cancelled.
create or replace function "better_supabase"."meeting_calendar_mirror"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_calendar uuid;
begin
  select y."id" into v_calendar from "better_supabase"."calendars" y
  where y."tenant_id" = new."tenant_id" and y."name" = 'Meetings'
  order by y."created_at"
  limit 1;
  if v_calendar is null then
    return new;
  end if;
  if new."status" not in ('planned', 'in_progress') then
    delete from "better_supabase"."calendar_events" x where x."calendar_id" = v_calendar and x."uid" = 'meeting-' || new."id"::text;
    return new;
  end if;
  insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "all_day", "tz", "status", "subject_type", "subject_id")
  values (new."tenant_id", v_calendar, 'meeting-' || new."id"::text, new."title",
    new."starts_at", coalesce(new."ends_at", new."starts_at" + interval '1 hour'), false, 'UTC', 'confirmed', 'meeting', new."id"::text)
  on conflict ("calendar_id", "uid", "original_start") do update set
    "title" = excluded."title", "starts_at" = excluded."starts_at",
    "ends_at" = excluded."ends_at", "updated_at" = now();
  return new;
end;
$$;
revoke execute on function "better_supabase"."meeting_calendar_mirror"() from public, anon, authenticated;
drop trigger if exists bsb_meeting_calendar on "better_supabase"."meetings";
create trigger bsb_meeting_calendar after insert or update of "starts_at", "ends_at", "title", "status" on "better_supabase"."meetings"
  for each row execute function "better_supabase"."meeting_calendar_mirror"();

-- Invites an attendee to the meeting's calendar event by their account email.
-- An attendee without an email is skipped. A chair becomes the event's chair.
create or replace function "better_supabase"."meeting_calendar_attendee"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event uuid;
  v_email text;
begin
  if tg_op = 'DELETE' then
    delete from "better_supabase"."calendar_attendees" y
    using "better_supabase"."calendar_events" x
    where x."uid" = 'meeting-' || old."meeting_id"::text
      and x."tenant_id" = old."tenant_id" and y."event_id" = x."id" and y."user_id" = old."user_id";
    return old;
  end if;
  select x."id" into v_event from "better_supabase"."calendar_events" x
  where x."tenant_id" = new."tenant_id" and x."uid" = 'meeting-' || new."meeting_id"::text
  limit 1;
  select u.email into v_email from auth.users u where u.id = new."user_id";
  if v_event is null or v_email is null then
    return new;
  end if;
  insert into "better_supabase"."calendar_attendees" ("tenant_id", "event_id", "email", "user_id", "role")
  values (new."tenant_id", v_event, v_email, new."user_id", case new."role" when 'chair' then 'chair' when 'guest' then 'optional' else 'required' end)
  on conflict ("event_id", "email") do update set "role" = excluded."role";
  return new;
end;
$$;
revoke execute on function "better_supabase"."meeting_calendar_attendee"() from public, anon, authenticated;
drop trigger if exists bsb_meeting_calendar_attendee on "better_supabase"."meeting_attendees";
create trigger bsb_meeting_calendar_attendee after insert or update of "role" or delete on "better_supabase"."meeting_attendees"
  for each row execute function "better_supabase"."meeting_calendar_attendee"();

-- Notifies a user invited to a planned or running meeting, unless they invited
-- themselves. The key keeps a later edit from notifying again.
create or replace function "better_supabase"."meeting_invitation_notice"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."meetings"%rowtype;
  v_claims text;
begin
  if new."user_id" is not distinct from auth.uid() then
    return new;
  end if;
  select * into v_row from "better_supabase"."meetings" x where x."id" = new."meeting_id";
  if not found or v_row."status" not in ('planned', 'in_progress') then
    return new;
  end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'meeting.invited',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'meeting',
      'subject_id', v_row."id"::text,
      'summary', v_row."title",
      'recipients', to_jsonb(array[new."user_id"]),
      'key', 'meeting.invited:' || v_row."id"::text || ':' || new."user_id"::text,
      'data', jsonb_build_object('meetingId', v_row."id", 'role', new."role", 'startsAt', v_row."starts_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."meeting_invitation_notice"() from public, anon, authenticated;
drop trigger if exists bsb_meeting_invitation on "better_supabase"."meeting_attendees";
create trigger bsb_meeting_invitation after insert on "better_supabase"."meeting_attendees"
  for each row execute function "better_supabase"."meeting_invitation_notice"();

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
drop policy if exists bsb_tenant_scope on "better_supabase"."meetings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."meetings";
create policy bsb_tenant_scope_select on "better_supabase"."meetings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meetings";
create policy bsb_tenant_scope_insert on "better_supabase"."meetings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."meetings";
create policy bsb_tenant_scope_update on "better_supabase"."meetings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meetings";
create policy bsb_tenant_scope_delete on "better_supabase"."meetings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_attendees";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_attendees";
create policy bsb_tenant_scope_select on "better_supabase"."meeting_attendees" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_attendees";
create policy bsb_tenant_scope_insert on "better_supabase"."meeting_attendees" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_attendees";
create policy bsb_tenant_scope_update on "better_supabase"."meeting_attendees" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_attendees";
create policy bsb_tenant_scope_delete on "better_supabase"."meeting_attendees" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_agenda_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_agenda_items";
create policy bsb_tenant_scope_select on "better_supabase"."meeting_agenda_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_agenda_items";
create policy bsb_tenant_scope_insert on "better_supabase"."meeting_agenda_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_agenda_items";
create policy bsb_tenant_scope_update on "better_supabase"."meeting_agenda_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_agenda_items";
create policy bsb_tenant_scope_delete on "better_supabase"."meeting_agenda_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_decisions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_decisions";
create policy bsb_tenant_scope_select on "better_supabase"."meeting_decisions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_decisions";
create policy bsb_tenant_scope_insert on "better_supabase"."meeting_decisions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_decisions";
create policy bsb_tenant_scope_update on "better_supabase"."meeting_decisions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_decisions";
create policy bsb_tenant_scope_delete on "better_supabase"."meeting_decisions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."meeting_action_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."meeting_action_items";
create policy bsb_tenant_scope_select on "better_supabase"."meeting_action_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('meetings.read'))) or "better_supabase"."meeting_role"("meeting_id") is not null)
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."meeting_action_items";
create policy bsb_tenant_scope_insert on "better_supabase"."meeting_action_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."meeting_action_items";
create policy bsb_tenant_scope_update on "better_supabase"."meeting_action_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."meeting_action_items";
create policy bsb_tenant_scope_delete on "better_supabase"."meeting_action_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

drop trigger if exists "bsb_search_meeting_index" on "better_supabase"."meetings";
create trigger "bsb_search_meeting_index"
  after insert or delete or update of "id", "tenant_id", "title", "location", "summary" on "better_supabase"."meetings"
  for each row execute function "better_supabase"."search_index_row"('meeting', 'id');

-- blocks.meetings.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

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

create or replace function "api"."meeting_role"(meeting_id uuid)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."meeting_role"($1) $$;
revoke execute on function "api"."meeting_role"(uuid) from public, anon;
grant execute on function "api"."meeting_role"(uuid) to authenticated, service_role;

create or replace function "api"."meeting_set_attendees"(meeting_id uuid, tenant uuid, team jsonb)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."meeting_set_attendees"($1, $2, $3) $$;
revoke execute on function "api"."meeting_set_attendees"(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."meeting_set_attendees"(uuid, uuid, jsonb) to service_role;

create or replace function "api"."create_meeting"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_meeting"($1, $2) $$;
revoke execute on function "api"."create_meeting"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_meeting"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."update_meeting"(meeting_id uuid, changes jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_meeting"($1, $2) $$;
revoke execute on function "api"."update_meeting"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_meeting"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."start_meeting"(meeting_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_meeting"($1) $$;
revoke execute on function "api"."start_meeting"(uuid) from public, anon;
grant execute on function "api"."start_meeting"(uuid) to authenticated, service_role;

create or replace function "api"."hold_meeting"(meeting_id uuid, summary text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."hold_meeting"($1, $2) $$;
revoke execute on function "api"."hold_meeting"(uuid, text) from public, anon;
grant execute on function "api"."hold_meeting"(uuid, text) to authenticated, service_role;

create or replace function "api"."cancel_meeting"(meeting_id uuid, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_meeting"($1, $2) $$;
revoke execute on function "api"."cancel_meeting"(uuid, text) from public, anon;
grant execute on function "api"."cancel_meeting"(uuid, text) to authenticated, service_role;

create or replace function "api"."delete_meeting"(meeting_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_meeting"($1) $$;
revoke execute on function "api"."delete_meeting"(uuid) from public, anon;
grant execute on function "api"."delete_meeting"(uuid) to authenticated, service_role;

create or replace function "api"."set_meeting_attendee"(meeting_id uuid, user_id uuid, role text default 'attendee', attendance text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_meeting_attendee"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_meeting_attendee"(uuid, uuid, text, text) from public, anon;
grant execute on function "api"."set_meeting_attendee"(uuid, uuid, text, text) to authenticated, service_role;

create or replace function "api"."remove_meeting_attendee"(meeting_id uuid, user_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_meeting_attendee"($1, $2) $$;
revoke execute on function "api"."remove_meeting_attendee"(uuid, uuid) from public, anon;
grant execute on function "api"."remove_meeting_attendee"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."save_meeting_agenda_item"(meeting_id uuid, item jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_meeting_agenda_item"($1, $2) $$;
revoke execute on function "api"."save_meeting_agenda_item"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_meeting_agenda_item"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_meeting_agenda_item"(item_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_meeting_agenda_item"($1) $$;
revoke execute on function "api"."delete_meeting_agenda_item"(uuid) from public, anon;
grant execute on function "api"."delete_meeting_agenda_item"(uuid) to authenticated, service_role;

create or replace function "api"."record_meeting_decision"(meeting_id uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_meeting_decision"($1, $2) $$;
revoke execute on function "api"."record_meeting_decision"(uuid, jsonb) from public, anon;
grant execute on function "api"."record_meeting_decision"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."decide_meeting_decision"(decision_id uuid, status text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_meeting_decision"($1, $2) $$;
revoke execute on function "api"."decide_meeting_decision"(uuid, text) from public, anon;
grant execute on function "api"."decide_meeting_decision"(uuid, text) to authenticated, service_role;

create or replace function "api"."add_meeting_action_item"(meeting_id uuid, task jsonb, assignees uuid[] default '{}', agenda_item_id uuid default null, decision_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_meeting_action_item"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."add_meeting_action_item"(uuid, jsonb, uuid[], uuid, uuid) from public, anon;
grant execute on function "api"."add_meeting_action_item"(uuid, jsonb, uuid[], uuid, uuid) to authenticated, service_role;

create or replace function "api"."get_meeting"(meeting_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_meeting"($1) $$;
revoke execute on function "api"."get_meeting"(uuid) from public, anon;
grant execute on function "api"."get_meeting"(uuid) to authenticated, service_role;

create or replace function "api"."list_meetings"(tenant uuid, filters jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_meetings"($1, $2) $$;
revoke execute on function "api"."list_meetings"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_meetings"(uuid, jsonb) to authenticated, service_role;

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
