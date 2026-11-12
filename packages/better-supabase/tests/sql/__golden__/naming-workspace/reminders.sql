-- ==== schema supabase/schemas/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block reminders@1 managed
-- @bsb-hash sha256:f74a6d33ca232c4e0bd40886f87c7d14e3363ee433d8c41b0decd4cc7e035455
-- Recurrence rules and reminders. Expansion follows RFC 5545 in TypeScript. Delivery is a job that records reminder.sent once per occurrence.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create table "better_supabase"."recurrence_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "dtstart" timestamptz not null,
  "tzid" text not null default 'UTC',
  "rrule" text,
  unique ("tenant_id", "subject_type", "subject_id")
);
alter table "better_supabase"."recurrence_rules" enable row level security;
revoke all on "better_supabase"."recurrence_rules" from public, anon, authenticated;
grant select on "better_supabase"."recurrence_rules" to authenticated;
grant all on "better_supabase"."recurrence_rules" to service_role;
create index "recurrence_rules_subject_idx" on "better_supabase"."recurrence_rules" ("subject_type", "subject_id");
create table "better_supabase"."reminders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "user_id" uuid,
  "method" text not null default 'notification',
  "offset_minutes" integer not null default 0
);
alter table "better_supabase"."reminders" add column "remind_at" timestamptz;
alter table "better_supabase"."reminders" enable row level security;
revoke all on "better_supabase"."reminders" from public, anon, authenticated;
grant select on "better_supabase"."reminders" to authenticated;
grant all on "better_supabase"."reminders" to service_role;
create index "reminders_subject_idx" on "better_supabase"."reminders" ("subject_type", "subject_id");
create index "reminders_tenant_idx" on "better_supabase"."reminders" ("tenant_id");
-- A negative offset fires after the occurrence; a year either way bounds it.
alter table "better_supabase"."reminders" add constraint bsb_reminders_offset_check
  check ("offset_minutes" >= -525600 and "offset_minutes" <= 525600);
create table "better_supabase"."reminder_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "reminder_id" uuid not null references "better_supabase"."reminders" ("id") on delete cascade,
  "occurrence_at" timestamptz not null,
  "sent_at" timestamptz,
  unique ("reminder_id", "occurrence_at")
);
alter table "better_supabase"."reminder_deliveries" enable row level security;
revoke all on "better_supabase"."reminder_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."reminder_deliveries" to authenticated;
grant all on "better_supabase"."reminder_deliveries" to service_role;
create or replace function "better_supabase"."save_reminder"(tenant uuid, subject_type text, subject_id text, offset_minutes integer, remind_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_reminder"(uuid, text, text, integer, timestamptz) to authenticated, service_role;

-- The caller's reminders on one subject, or on every subject when both are
-- null, the earliest first.
create or replace function "better_supabase"."list_my_reminders"(tenant uuid, subject_type text default null, subject_id text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_my_reminders.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id",
      'subjectType', r."subject_type",
      'subjectId', r."subject_id",
      'method', r."method",
      'offsetMinutes', r."offset_minutes",
      'remindAt', r."remind_at"
    ) order by r."offset_minutes" desc, r."id"), '[]'::jsonb)
    from "better_supabase"."reminders" r
    where r."tenant_id" = list_my_reminders.tenant
      and (list_my_reminders.subject_type is null
        or r."subject_type" = list_my_reminders.subject_type)
      and (list_my_reminders.subject_id is null
        or r."subject_id" = list_my_reminders.subject_id)
      and r."user_id" = auth.uid()
  );
end;
$$;
revoke execute on function "better_supabase"."list_my_reminders"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."list_my_reminders"(uuid, text, text) to authenticated, service_role;

-- Removes one of the caller's reminders, with its delivery history.
create or replace function "better_supabase"."delete_reminder"(reminder uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select r."tenant_id" into v_tenant
    from "better_supabase"."reminders" r
    where r."id" = delete_reminder.reminder
      and (auth.role() = 'service_role' or r."user_id" = auth.uid());
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  delete from "better_supabase"."reminders" r where r."id" = delete_reminder.reminder;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_reminder"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_reminder"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."mark_reminder_sent"(reminder uuid, occurrence_at timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_subject_type text;
  v_subject_id text;
  v_user uuid;
begin
  select "tenant_id", "subject_type", "subject_id", "user_id"
    into v_tenant, v_subject_type, v_subject_id, v_user
    from "better_supabase"."reminders" where "id" = mark_reminder_sent.reminder;
  if not found then
    raise exception 'reminder not found' using errcode = 'P0002', hint = 'REMINDER_NOT_FOUND';
  end if;
  insert into "better_supabase"."reminder_deliveries" ("reminder_id", "occurrence_at", "sent_at")
  values (mark_reminder_sent.reminder, mark_reminder_sent.occurrence_at, now())
  on conflict ("reminder_id", "occurrence_at") do nothing;
  -- A second delivery of the same occurrence records nothing.
  if not found then
    return false;
  end if;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."mark_reminder_sent"(uuid, timestamptz) to service_role;

-- Every reminder's schedule: its subject's rule, its own time, or the
-- subject's `at` column. Delivery dedupes on (reminder, occurrence).

create function "better_supabase"."list_reminder_schedule"()
returns table (
  reminder uuid,
  dtstart timestamptz,
  tzid text,
  rrule text,
  offset_minutes integer,
  tenant uuid,
  subject_type text,
  subject_id text,
  user_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select r."id",
    u."dtstart",
    u."tzid",
    u."rrule",
    r."offset_minutes",
    r."tenant_id",
    r."subject_type",
    r."subject_id",
    r."user_id"
  from "better_supabase"."reminders" r
  join "better_supabase"."recurrence_rules" u
    on u."tenant_id" = r."tenant_id"
   and u."subject_type" = r."subject_type"
   and u."subject_id" = r."subject_id"
  where r."remind_at" is null
  union all
  select r."id", r."remind_at", 'UTC'::text, 'FREQ=DAILY;COUNT=1'::text, 0,
    r."tenant_id", r."subject_type",
    r."subject_id", r."user_id"
  from "better_supabase"."reminders" r
  where r."remind_at" is not null;
$$;
revoke execute on function "better_supabase"."list_reminder_schedule"() from public, anon, authenticated;
grant execute on function "better_supabase"."list_reminder_schedule"() to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."recurrence_rules" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."recurrence_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."recurrence_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."recurrence_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."reminders" as restrictive
  for select to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_insert on "better_supabase"."reminders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."reminders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."reminders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

-- ==== data supabase/better-supabase-data/900_better_supabase_063_reminders.sql
-- better-supabase module: reminders
-- @bsb-block-data reminders
-- @bsb-hash sha256:d2fe5d73d65cd57fa991248140b2f47de077d33f44e6e190b9e0d3012d0ab3b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('reminders', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
