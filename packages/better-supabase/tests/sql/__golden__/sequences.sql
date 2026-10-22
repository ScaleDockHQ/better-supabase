-- ==== alone: schema supabase/schemas/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block sequences@1 managed
-- Multi-step outreach sequences whose steps send email through mail-sync, create work items or wait. Each sequence runs as an enrollment program, and a reply on the thread or from the recipient's address ends their run.
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
-- Outreach sequences: steps that send email, create a task or wait. Each
-- sequence runs as the enrollment program sequence:<id>, whose steps are the
-- sequence's steps; a reply ends a recipient's run.
create table if not exists "better_supabase"."sequences" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'active', 'paused', 'archived')),
  -- An inbound message on the thread, or from the recipient's address, ends
  -- the recipient's run.
  "exit_on_reply" boolean not null default true,
  -- The mailbox email steps send from when the enrollment names none.
  "mail_account_id" uuid,
  -- The steps in order: [{ id, kind: email | task | wait, ... }]. Each is a
  -- step of the enrollment program sequence:<id>.
  "steps" jsonb not null default '[]' check (jsonb_typeof("steps") = 'array'),
  "version" integer not null default 1 check ("version" >= 1),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint "sequences_key_key" unique ("tenant_id", "key")
);
create index if not exists "sequences_account_idx" on "better_supabase"."sequences" ("mail_account_id") where "mail_account_id" is not null;

-- Where a recipient is in a sequence. The enrollment holds the completed
-- steps; this holds the next step, when it runs and who it goes to.
create table if not exists "better_supabase"."sequence_enrollments" (
  "enrollment_id" uuid primary key references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "sequence_id" uuid not null references "better_supabase"."sequences" ("id") on delete cascade,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "address" text check ("address" is null or (length("address") <= 320 and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  "name" text check ("name" is null or length("name") <= 200),
  "mail_account_id" uuid,
  -- The thread the first email started; later emails reply on it.
  "mail_thread_id" uuid,
  -- The step that runs next, null once every step is done.
  "step" text,
  "next_run_at" timestamptz,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'completed', 'exited')),
  "exit_reason" text check ("exit_reason" is null or "exit_reason" in ('replied', 'manual', 'failed', 'archived')),
  "attempts" integer not null default 0 check ("attempts" >= 0),
  "last_error" text check ("last_error" is null or length("last_error") <= 2000),
  -- Values for the {{key}} placeholders of the email steps.
  "variables" jsonb not null default '{}' check (jsonb_typeof("variables") = 'object'),
  "enrolled_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("status" = 'exited') = ("exit_reason" is not null))
);
create index if not exists "sequence_enrollments_parent_idx" on "better_supabase"."sequence_enrollments" ("sequence_id", "status");
create index if not exists "sequence_enrollments_due_idx" on "better_supabase"."sequence_enrollments" ("next_run_at") where "status" = 'active';
create index if not exists "sequence_enrollments_subject_idx" on "better_supabase"."sequence_enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "sequence_enrollments_address_idx" on "better_supabase"."sequence_enrollments" ("tenant_id", lower("address")) where "status" in ('active', 'paused');
create index if not exists "sequence_enrollments_account_idx" on "better_supabase"."sequence_enrollments" ("mail_account_id") where "mail_account_id" is not null;
create index if not exists "sequence_enrollments_thread_idx" on "better_supabase"."sequence_enrollments" ("mail_thread_id") where "mail_thread_id" is not null;

alter table "better_supabase"."sequences" enable row level security;
revoke all on "better_supabase"."sequences" from anon, authenticated;
grant select on "better_supabase"."sequences" to authenticated;
grant all on "better_supabase"."sequences" to service_role;
drop policy if exists "sequences_read" on "better_supabase"."sequences";
create policy "sequences_read" on "better_supabase"."sequences" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));
alter table "better_supabase"."sequence_enrollments" enable row level security;
revoke all on "better_supabase"."sequence_enrollments" from anon, authenticated;
grant select on "better_supabase"."sequence_enrollments" to authenticated;
grant all on "better_supabase"."sequence_enrollments" to service_role;
drop policy if exists "sequence_enrollments_read" on "better_supabase"."sequence_enrollments";
create policy "sequence_enrollments_read" on "better_supabase"."sequence_enrollments" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));

-- Checks a steps array: [{ id, kind, ... }] where an email step has a
-- subject and text or html, a task step a title, and a wait step minutes.
create or replace function "better_supabase"."sequence_steps_check"(steps jsonb, mail boolean)
returns void
language plpgsql
immutable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_step jsonb;
  v_ids text[] := '{}';
  v_id text;
begin
  if sequence_steps_check.steps is null or jsonb_typeof(sequence_steps_check.steps) <> 'array' then
    raise exception 'steps must be an array' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_array_length(sequence_steps_check.steps) > 50 then
    raise exception 'a sequence has at most 50 steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(sequence_steps_check.steps) t loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'each step must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_id := v_step ->> 'id';
    if v_id is null or v_id !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
      raise exception 'step id: use lowercase letters, digits, "_" or "-"' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    if v_id = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_ids := v_ids || v_id;
    case v_step ->> 'kind'
      when 'wait' then
        if jsonb_typeof(v_step -> 'minutes') is distinct from 'number'
          or (v_step ->> 'minutes')::numeric <> trunc((v_step ->> 'minutes')::numeric)
          or (v_step ->> 'minutes')::numeric not between 1 and 525600 then
          raise exception 'a wait step waits 1 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'email' then
        if not sequence_steps_check.mail then
          raise exception 'email steps need the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(trim(v_step ->> 'subject'), '')) not between 1 and 300 then
          raise exception 'an email step needs a subject of 1 to 300 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if coalesce(v_step ->> 'text', v_step ->> 'html') is null then
          raise exception 'an email step needs text or html' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'text', '')) + length(coalesce(v_step ->> 'html', '')) > 200000 then
          raise exception 'an email step''s body is at most 200000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'track' and jsonb_typeof(v_step -> 'track') <> 'boolean' then
          raise exception 'track must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'templateVersionId' and coalesce(v_step ->> 'templateVersionId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          raise exception 'templateVersionId must be a uuid' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'task' then
        if length(coalesce(trim(v_step ->> 'title'), '')) not between 1 and 200 then
          raise exception 'a task step needs a title of 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'body', '')) > 10000 then
          raise exception 'a task step''s body is at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'dueInMinutes' and (jsonb_typeof(v_step -> 'dueInMinutes') is distinct from 'number'
          or (v_step ->> 'dueInMinutes')::numeric <> trunc((v_step ->> 'dueInMinutes')::numeric)
          or (v_step ->> 'dueInMinutes')::numeric not between 0 and 525600) then
          raise exception 'dueInMinutes must be 0 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      else
        raise exception 'a step''s kind must be email, task or wait' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end case;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."sequence_steps_check"(jsonb, boolean) from public, anon, authenticated;

-- A recipient in a sequence with their completed steps.
create or replace function "better_supabase"."sequence_member_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."enrollment_id", 'organizationId', x."tenant_id", 'sequenceId', x."sequence_id",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'name', x."name",
    'accountId', x."mail_account_id", 'threadId', x."mail_thread_id", 'step', x."step", 'nextRunAt', x."next_run_at",
    'status', x."status", 'exitReason', x."exit_reason", 'attempts', x."attempts", 'lastError', x."last_error",
    'variables', x."variables", 'enrolledBy', x."enrolled_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
    'completedSteps', coalesce((select jsonb_agg(y."step" order by y."completed_at", y."step") from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."enrollment_id"), '[]'::jsonb))
  from "better_supabase"."sequence_enrollments" x
  where x."enrollment_id" = sequence_member_json.enrollment_id;
$$;
revoke execute on function "better_supabase"."sequence_member_json"(uuid) from public, anon, authenticated;

-- Moves a recipient to their first step not done: a wait step runs once its
-- minutes pass, the others right away. With every step done the run
-- completes. A recipient already on that step keeps their schedule.
create or replace function "better_supabase"."sequence_place"(enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
  v_steps jsonb;
  v_next jsonb;
begin
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_place.enrollment_id for update;
  if v_member."enrollment_id" is null or v_member."status" in ('completed', 'exited') then
    return;
  end if;
  select y."steps" into v_steps from "better_supabase"."sequences" y where y."id" = v_member."sequence_id";
  select t.value into v_next
  from jsonb_array_elements(coalesce(v_steps, '[]'::jsonb)) with ordinality as t(value, ord)
  where not exists (select 1 from "better_supabase"."enrollment_steps" z where z."enrollment_id" = v_member."enrollment_id" and z."step" = t.value ->> 'id')
  order by t.ord
  limit 1;
  if v_next is null then
    update "better_supabase"."sequence_enrollments" x
    set "status" = 'completed', "step" = null, "next_run_at" = null, "attempts" = 0, "last_error" = null, "updated_at" = now()
    where x."enrollment_id" = v_member."enrollment_id"
    returning * into v_member;
    null;
    return;
  end if;
  if (v_next ->> 'id') is not distinct from v_member."step" then
    return;
  end if;
  update "better_supabase"."sequence_enrollments" x
  set "step" = v_next ->> 'id',
    "next_run_at" = case when v_next ->> 'kind' = 'wait' then now() + make_interval(mins => (v_next ->> 'minutes')::integer) else now() end,
    "attempts" = 0, "last_error" = null, "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id";
end;
$$;
revoke execute on function "better_supabase"."sequence_place"(uuid) from public, anon, authenticated;

-- Ends a recipient's run (reason: replied, manual, failed or archived) and
-- cancels their enrollment; the completed steps stay.
create or replace function "better_supabase"."sequence_exit"(enrollment_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  update "better_supabase"."sequence_enrollments" x
  set "status" = 'exited', "exit_reason" = sequence_exit.reason, "next_run_at" = null, "updated_at" = now()
  where x."enrollment_id" = sequence_exit.enrollment_id and x."status" in ('active', 'paused')
  returning * into v_member;
  if v_member."enrollment_id" is null then
    return;
  end if;
  update "better_supabase"."enrollments" x
  set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
  where x."id" = v_member."enrollment_id" and x."status" <> 'cancelled';
  if sequence_exit.reason = 'manual' then
    null;
  else
    null;
  end if;
end;
$$;
revoke execute on function "better_supabase"."sequence_exit"(uuid, text) from public, anon, authenticated;

-- Marks the recipient's current step done and moves them on.
create or replace function "better_supabase"."sequence_step_done"(enrollment_id uuid, step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  perform "better_supabase"."enrollment_mark"(sequence_step_done.enrollment_id, sequence_step_done.step, true, null);
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_done.enrollment_id;
  null;
  perform "better_supabase"."sequence_place"(sequence_step_done.enrollment_id);
end;
$$;
revoke execute on function "better_supabase"."sequence_step_done"(uuid, text) from public, anon, authenticated;

-- Gives every running recipient of a sequence its current steps and moves
-- them to their first step not done.
create or replace function "better_supabase"."sequence_resync"(sequence_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "better_supabase"."sequences";
  v_member "better_supabase"."sequence_enrollments";
begin
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = sequence_resync.sequence_id;
  for v_member in
    select * from "better_supabase"."sequence_enrollments" x
    where x."sequence_id" = sequence_resync.sequence_id and x."status" in ('active', 'paused')
    for update
  loop
    perform "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
      v_member."subject_type", v_member."subject_id", null);
    perform "better_supabase"."sequence_place"(v_member."enrollment_id");
  end loop;
end;
$$;
revoke execute on function "better_supabase"."sequence_resync"(uuid) from public, anon, authenticated;

-- Creates or changes a sequence. sequence is { id?, key, name,
-- description, status, exitOnReply, accountId, steps }; keys left out keep
-- their value. Changing the steps raises the version and moves running
-- recipients onto the new steps. Archiving ends every run.
create or replace function "better_supabase"."save_sequence"(tenant uuid, sequence jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."sequences";
  v_row "better_supabase"."sequences";
  v_key text;
  v_name text;
  v_description text;
  v_status text;
  v_exit boolean;
  v_account uuid;
  v_steps jsonb;
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_sequence.tenant is not null and coalesce(better_supabase.can('tenant', save_sequence.tenant, 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if save_sequence.sequence is null or jsonb_typeof(save_sequence.sequence) <> 'object' then
    raise exception 'sequence must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_id := nullif(save_sequence.sequence ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."sequences" x
    where x."id" = v_id and x."tenant_id" = save_sequence.tenant
    for update;
    if v_old."id" is null then
      raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_sequence.sequence ->> 'key', v_old."key");
  v_name := trim(coalesce(save_sequence.sequence ->> 'name', v_old."name"));
  v_description := case when save_sequence.sequence ? 'description'
    then nullif(trim(save_sequence.sequence ->> 'description'), '') else v_old."description" end;
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old."status", 'draft');
  v_exit := case when save_sequence.sequence ? 'exitOnReply'
    then (save_sequence.sequence ->> 'exitOnReply')::boolean else coalesce(v_old."exit_on_reply", true) end;
  v_account := case when save_sequence.sequence ? 'accountId'
    then nullif(save_sequence.sequence ->> 'accountId', '')::uuid else v_old."mail_account_id" end;
  v_steps := case when save_sequence.sequence ? 'steps'
    then save_sequence.sequence -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a sequence''s key can''t change' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'status must be draft, active, paused or archived' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_exit is null then
    raise exception 'exitOnReply must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  perform "better_supabase"."sequence_steps_check"(v_steps, false);
  if v_status = 'active' and jsonb_array_length(v_steps) = 0 then
    raise exception 'an active sequence needs at least one step' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null then
    raise exception 'accountId needs the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."sequences" ("tenant_id", "key", "name", "description", "status", "exit_on_reply", "mail_account_id", "steps", "created_by")
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."sequences" x
    set "name" = v_name, "description" = v_description, "status" = v_status, "exit_on_reply" = v_exit,
      "mail_account_id" = v_account, "steps" = v_steps,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
    if v_old."steps" is distinct from v_row."steps" then
      perform "better_supabase"."sequence_resync"(v_row."id");
    end if;
    if v_row."status" = 'archived' and v_old."status" <> 'archived' then
      for v_member in
        select * from "better_supabase"."sequence_enrollments" x
        where x."sequence_id" = v_row."id" and x."status" in ('active', 'paused')
      loop
        perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'archived');
      end loop;
    end if;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."save_sequence"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_sequence"(uuid, jsonb) to authenticated, service_role;

-- An organization's sequences with their recipient counts, by name. status
-- filters; without it archived sequences stay out.
create or replace function "better_supabase"."list_sequences"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequences.tenant is not null and coalesce(better_supabase.can('tenant', list_sequences.tenant, 'sequences.read'), false))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = x."id")) order by x."name", x."id")
    from "better_supabase"."sequences" x
    where x."tenant_id" = list_sequences.tenant
      and (case when list_sequences.status is null then x."status" <> 'archived' else x."status" = list_sequences.status end)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_sequences"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_sequences"(uuid, text) to authenticated, service_role;

-- One sequence with its recipient counts.
create or replace function "better_supabase"."get_sequence"(sequence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."sequences";
begin
  select * into v_row from "better_supabase"."sequences" x where x."id" = get_sequence.sequence_id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.read'), false))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_sequence"(uuid) from public, anon;
grant execute on function "better_supabase"."get_sequence"(uuid) to authenticated, service_role;

-- Deletes a sequence with its enrollments; false when there was none.
create or replace function "better_supabase"."delete_sequence"(sequence_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."sequences";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."sequences" x where x."id" = delete_sequence.sequence_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = ('sequence:' || v_row."id"::text);
  delete from "better_supabase"."sequences" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_sequence"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_sequence"(uuid) to authenticated, service_role;

-- Enrolls a record (subject_type, subject_id) in an active sequence. attrs
-- is { address, name, accountId, variables }: a person's email and name fill
-- address and name when left out, and the mailbox defaults to the
-- sequence's, then the caller's. A finished or exited run starts over.
create or replace function "better_supabase"."enroll_in_sequence"(sequence_id uuid, subject_type text, subject_id text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "better_supabase"."sequences";
  v_row "better_supabase"."enrollments";
  v_member "better_supabase"."sequence_enrollments";
  v_attrs jsonb := coalesce(enroll_in_sequence.attrs, '{}'::jsonb);
  v_address text;
  v_name text;
  v_email text;
  v_label text;
  v_account uuid;
  v_owner uuid;
  v_variables jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = enroll_in_sequence.sequence_id;
  if v_sequence."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to enroll in sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if v_sequence."status" <> 'active' then
    raise exception 'only an active sequence takes enrollments' using errcode = '55000', hint = 'SEQUENCE_NOT_ACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_type is null or enroll_in_sequence.subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'subject_type: use lowercase letters, digits or _' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_id is null or length(enroll_in_sequence.subject_id) not between 1 and 200 then
    raise exception 'subject_id must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_address := nullif(trim(v_attrs ->> 'address'), '');
  v_name := nullif(trim(v_attrs ->> 'name'), '');
  v_account := nullif(v_attrs ->> 'accountId', '')::uuid;
  v_variables := coalesce(v_attrs -> 'variables', '{}'::jsonb);
  
  if v_address is not null and (length(v_address) > 320 or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$') then
    raise exception 'address must be an email address' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_name) > 200 then
    raise exception 'name must be at most 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_typeof(v_variables) <> 'object' or length(v_variables::text) > 10000 then
    raise exception 'variables must be an object of at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_address is null and exists (select 1 from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'kind' = 'email') then
    raise exception 'the recipient needs an email address for the sequence''s email steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null then
    raise exception 'accountId needs the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_sequence."tenant_id" and x."program" = ('sequence:' || v_sequence."id"::text)
    and x."subject_type" = enroll_in_sequence.subject_type and x."subject_id" = enroll_in_sequence.subject_id
  for update;
  if v_row."id" is not null then
    select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_row."id" for update;
    if v_member."status" in ('active', 'paused') then
      return "better_supabase"."sequence_member_json"(v_row."id");
    end if;
    -- Starting over: clearing the steps makes enrollment_ensure take the
    -- current ones, with none done.
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id";
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "completed_at" = null, "enrolled_by" = auth.uid(),
      "enrolled_at" = now(), "steps" = '{}'
    where x."id" = v_row."id";
  end if;
  v_id := "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
    enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  insert into "better_supabase"."sequence_enrollments" ("enrollment_id", "tenant_id", "sequence_id", "subject_type", "subject_id", "address", "name",
    "mail_account_id", "variables", "enrolled_by")
  values (v_id, v_sequence."tenant_id", v_sequence."id", enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, v_address, v_name,
    v_account, v_variables, auth.uid())
  on conflict ("enrollment_id") do update
  set "address" = excluded."address", "name" = excluded."name", "mail_account_id" = excluded."mail_account_id",
    "variables" = excluded."variables", "enrolled_by" = excluded."enrolled_by", "status" = 'active',
    "exit_reason" = null, "step" = null, "next_run_at" = null, "mail_thread_id" = null, "attempts" = 0,
    "last_error" = null, "updated_at" = now();
  perform "better_supabase"."sequence_place"(v_id);
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_id;
  null;
  return "better_supabase"."sequence_member_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll_in_sequence"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."enroll_in_sequence"(uuid, text, text, jsonb) to authenticated, service_role;

-- Pauses, resumes or exits a recipient's run (action: pause, resume, exit).
create or replace function "better_supabase"."change_sequence_enrollment"(enrollment_id uuid, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = change_sequence_enrollment.enrollment_id for update;
  if v_member."enrollment_id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to change sequence enrollments' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  case change_sequence_enrollment.action
    when 'pause' then
      if v_member."status" <> 'active' then
        raise exception 'only an active run can be paused' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "better_supabase"."sequence_enrollments" x set "status" = 'paused', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      null;
    when 'resume' then
      if v_member."status" <> 'paused' then
        raise exception 'only a paused run can be resumed' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "better_supabase"."sequence_enrollments" x set "status" = 'active', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      null;
    when 'exit' then
      if v_member."status" not in ('active', 'paused') then
        raise exception 'only an active or paused run can be exited' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'manual');
    else
      raise exception 'action must be pause, resume or exit' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end case;
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) from public, anon;
grant execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) to authenticated, service_role;

-- An organization's sequence recipients, newest first. filter is
-- { sequence, subjectType, subjectId, status, limit, before }: before is a
-- createdAt from the previous page.
create or replace function "better_supabase"."list_sequence_enrollments"(tenant uuid, filter jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_sequence_enrollments.filter, '{}'::jsonb);
  v_parent uuid := nullif(v_filter ->> 'sequence', '')::uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.enroll'), false)))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filter) <> 'object' then
    raise exception 'filter must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."sequence_member_json"(y."enrollment_id") order by y."created_at" desc, y."enrollment_id" desc)
    from (
      select x."enrollment_id", x."created_at"
      from "better_supabase"."sequence_enrollments" x
      where x."tenant_id" = list_sequence_enrollments.tenant
        and (v_parent is null or x."sequence_id" = v_parent)
        and (v_filter ->> 'subjectType' is null or x."subject_type" = v_filter ->> 'subjectType')
        and (v_filter ->> 'subjectId' is null or x."subject_id" = v_filter ->> 'subjectId')
        and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
        and (v_filter ->> 'before' is null or x."created_at" < (v_filter ->> 'before')::timestamptz)
      order by x."created_at" desc, x."enrollment_id" desc
      limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_sequence_enrollments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_sequence_enrollments"(uuid, jsonb) to authenticated, service_role;

-- Runs the steps that are due, oldest first: wait steps finish, task steps
-- create a work item for whoever enrolled the recipient, and email steps
-- are claimed for 10 minutes and returned for the caller to send. Call
-- sequence_step_sent or sequence_step_failed with each result. Returns
-- { ran, emails: [{ enrollmentId, sequenceId, organizationId, accountId,
-- threadId, to, step, variables, attempt, subjectType, subjectId }] }.
create or replace function "better_supabase"."run_due_sequences"(max_count integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_due "better_supabase"."sequence_enrollments";
  v_member "better_supabase"."sequence_enrollments";
  v_sequence "better_supabase"."sequences";
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  for v_due in
    select x.* from "better_supabase"."sequence_enrollments" x
    join "better_supabase"."sequences" y on y."id" = x."sequence_id"
    where x."status" = 'active' and x."next_run_at" <= now() and y."status" = 'active'
    order by x."next_run_at", x."enrollment_id"
    limit least(greatest(coalesce(run_due_sequences.max_count, 50), 1), 500)
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_due."enrollment_id";
      exit when v_member."status" <> 'active' or v_member."step" is null or v_member."next_run_at" > now();
      select * into v_sequence from "better_supabase"."sequences" x where x."id" = v_member."sequence_id";
      v_step := (select t.value from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'id' = v_member."step");
      if v_step is null then
        perform "better_supabase"."sequence_place"(v_member."enrollment_id");
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        update "better_supabase"."sequence_enrollments" x
        set "attempts" = x."attempts" + 1, "next_run_at" = now() + interval '10 minutes', "updated_at" = now()
        where x."enrollment_id" = v_member."enrollment_id"
        returning * into v_member;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'organizationId', v_member."tenant_id",
          'accountId', coalesce(v_member."mail_account_id", v_sequence."mail_account_id"), 'threadId', v_member."mail_thread_id",
          'to', jsonb_build_object('address', v_member."address", 'name', v_member."name"),
          'step', v_step, 'variables', v_member."variables", 'attempt', v_member."attempts",
          'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id"));
        exit;
      end if;
      perform "better_supabase"."sequence_step_done"(v_member."enrollment_id", v_member."step");
      v_ran := v_ran + 1;
    end loop;
  end loop;
  return jsonb_build_object('ran', v_ran, 'emails', v_emails);
end;
$$;
revoke execute on function "better_supabase"."run_due_sequences"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."run_due_sequences"(integer) to service_role;

-- Records that a claimed email step went out as message_id (a mail-sync
-- message, or null): later emails reply on its thread. A stale result, for
-- a run that moved on, changes nothing.
create or replace function "better_supabase"."sequence_step_sent"(enrollment_id uuid, step text, message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_sent.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_sent.step then
    return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
  end if;
  perform "better_supabase"."sequence_step_done"(v_member."enrollment_id", sequence_step_sent.step);
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."sequence_step_sent"(uuid, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."sequence_step_sent"(uuid, text, uuid) to service_role;

-- Records that a claimed email step failed to send: it runs again after
-- 15 minutes times the attempts, and the run exits as failed after
-- 3 attempts.
create or replace function "better_supabase"."sequence_step_failed"(enrollment_id uuid, step text, error text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_failed.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_failed.step then
    return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
  end if;
  update "better_supabase"."sequence_enrollments" x
  set "last_error" = left(coalesce(sequence_step_failed.error, 'send failed'), 2000),
    "next_run_at" = now() + make_interval(mins => 15 * greatest(x."attempts", 1)),
    "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id"
  returning * into v_member;
  if v_member."attempts" >= 3 then
    perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'failed');
  end if;
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."sequence_step_failed"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sequence_step_failed"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block-data sequences
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sequences', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block sequences@1 managed
-- Multi-step outreach sequences whose steps send email through mail-sync, create work items or wait. Each sequence runs as an enrollment program, and a reply on the thread or from the recipient's address ends their run.
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
-- Outreach sequences: steps that send email, create a task or wait. Each
-- sequence runs as the enrollment program sequence:<id>, whose steps are the
-- sequence's steps; a reply ends a recipient's run.
create table if not exists "better_supabase"."sequences" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'active', 'paused', 'archived')),
  -- An inbound message on the thread, or from the recipient's address, ends
  -- the recipient's run.
  "exit_on_reply" boolean not null default true,
  -- The mailbox email steps send from when the enrollment names none.
  "mail_account_id" uuid references "better_supabase"."mail_accounts" ("id") on delete set null,
  -- The steps in order: [{ id, kind: email | task | wait, ... }]. Each is a
  -- step of the enrollment program sequence:<id>.
  "steps" jsonb not null default '[]' check (jsonb_typeof("steps") = 'array'),
  "version" integer not null default 1 check ("version" >= 1),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint "sequences_key_key" unique ("tenant_id", "key")
);
create index if not exists "sequences_account_idx" on "better_supabase"."sequences" ("mail_account_id") where "mail_account_id" is not null;

-- Where a recipient is in a sequence. The enrollment holds the completed
-- steps; this holds the next step, when it runs and who it goes to.
create table if not exists "better_supabase"."sequence_enrollments" (
  "enrollment_id" uuid primary key references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "sequence_id" uuid not null references "better_supabase"."sequences" ("id") on delete cascade,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "address" text check ("address" is null or (length("address") <= 320 and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  "name" text check ("name" is null or length("name") <= 200),
  "mail_account_id" uuid references "better_supabase"."mail_accounts" ("id") on delete set null,
  -- The thread the first email started; later emails reply on it.
  "mail_thread_id" uuid references "better_supabase"."mail_threads" ("id") on delete set null,
  -- The step that runs next, null once every step is done.
  "step" text,
  "next_run_at" timestamptz,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'completed', 'exited')),
  "exit_reason" text check ("exit_reason" is null or "exit_reason" in ('replied', 'manual', 'failed', 'archived')),
  "attempts" integer not null default 0 check ("attempts" >= 0),
  "last_error" text check ("last_error" is null or length("last_error") <= 2000),
  -- Values for the {{key}} placeholders of the email steps.
  "variables" jsonb not null default '{}' check (jsonb_typeof("variables") = 'object'),
  "enrolled_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("status" = 'exited') = ("exit_reason" is not null))
);
create index if not exists "sequence_enrollments_parent_idx" on "better_supabase"."sequence_enrollments" ("sequence_id", "status");
create index if not exists "sequence_enrollments_due_idx" on "better_supabase"."sequence_enrollments" ("next_run_at") where "status" = 'active';
create index if not exists "sequence_enrollments_subject_idx" on "better_supabase"."sequence_enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "sequence_enrollments_address_idx" on "better_supabase"."sequence_enrollments" ("tenant_id", lower("address")) where "status" in ('active', 'paused');
create index if not exists "sequence_enrollments_account_idx" on "better_supabase"."sequence_enrollments" ("mail_account_id") where "mail_account_id" is not null;
create index if not exists "sequence_enrollments_thread_idx" on "better_supabase"."sequence_enrollments" ("mail_thread_id") where "mail_thread_id" is not null;

alter table "better_supabase"."sequences" enable row level security;
revoke all on "better_supabase"."sequences" from anon, authenticated;
grant select on "better_supabase"."sequences" to authenticated;
grant all on "better_supabase"."sequences" to service_role;
drop policy if exists "sequences_read" on "better_supabase"."sequences";
create policy "sequences_read" on "better_supabase"."sequences" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));
alter table "better_supabase"."sequence_enrollments" enable row level security;
revoke all on "better_supabase"."sequence_enrollments" from anon, authenticated;
grant select on "better_supabase"."sequence_enrollments" to authenticated;
grant all on "better_supabase"."sequence_enrollments" to service_role;
drop policy if exists "sequence_enrollments_read" on "better_supabase"."sequence_enrollments";
create policy "sequence_enrollments_read" on "better_supabase"."sequence_enrollments" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));

-- Checks a steps array: [{ id, kind, ... }] where an email step has a
-- subject and text or html, a task step a title, and a wait step minutes.
create or replace function "better_supabase"."sequence_steps_check"(steps jsonb, mail boolean)
returns void
language plpgsql
immutable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_step jsonb;
  v_ids text[] := '{}';
  v_id text;
begin
  if sequence_steps_check.steps is null or jsonb_typeof(sequence_steps_check.steps) <> 'array' then
    raise exception 'steps must be an array' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_array_length(sequence_steps_check.steps) > 50 then
    raise exception 'a sequence has at most 50 steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(sequence_steps_check.steps) t loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'each step must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_id := v_step ->> 'id';
    if v_id is null or v_id !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
      raise exception 'step id: use lowercase letters, digits, "_" or "-"' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    if v_id = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_ids := v_ids || v_id;
    case v_step ->> 'kind'
      when 'wait' then
        if jsonb_typeof(v_step -> 'minutes') is distinct from 'number'
          or (v_step ->> 'minutes')::numeric <> trunc((v_step ->> 'minutes')::numeric)
          or (v_step ->> 'minutes')::numeric not between 1 and 525600 then
          raise exception 'a wait step waits 1 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'email' then
        if not sequence_steps_check.mail then
          raise exception 'email steps need the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(trim(v_step ->> 'subject'), '')) not between 1 and 300 then
          raise exception 'an email step needs a subject of 1 to 300 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if coalesce(v_step ->> 'text', v_step ->> 'html') is null then
          raise exception 'an email step needs text or html' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'text', '')) + length(coalesce(v_step ->> 'html', '')) > 200000 then
          raise exception 'an email step''s body is at most 200000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'track' and jsonb_typeof(v_step -> 'track') <> 'boolean' then
          raise exception 'track must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'templateVersionId' and coalesce(v_step ->> 'templateVersionId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          raise exception 'templateVersionId must be a uuid' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'task' then
        if length(coalesce(trim(v_step ->> 'title'), '')) not between 1 and 200 then
          raise exception 'a task step needs a title of 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'body', '')) > 10000 then
          raise exception 'a task step''s body is at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'dueInMinutes' and (jsonb_typeof(v_step -> 'dueInMinutes') is distinct from 'number'
          or (v_step ->> 'dueInMinutes')::numeric <> trunc((v_step ->> 'dueInMinutes')::numeric)
          or (v_step ->> 'dueInMinutes')::numeric not between 0 and 525600) then
          raise exception 'dueInMinutes must be 0 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      else
        raise exception 'a step''s kind must be email, task or wait' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end case;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."sequence_steps_check"(jsonb, boolean) from public, anon, authenticated;

-- A recipient in a sequence with their completed steps.
create or replace function "better_supabase"."sequence_member_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."enrollment_id", 'organizationId', x."tenant_id", 'sequenceId', x."sequence_id",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'name', x."name",
    'accountId', x."mail_account_id", 'threadId', x."mail_thread_id", 'step', x."step", 'nextRunAt', x."next_run_at",
    'status', x."status", 'exitReason', x."exit_reason", 'attempts', x."attempts", 'lastError', x."last_error",
    'variables', x."variables", 'enrolledBy', x."enrolled_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
    'completedSteps', coalesce((select jsonb_agg(y."step" order by y."completed_at", y."step") from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."enrollment_id"), '[]'::jsonb))
  from "better_supabase"."sequence_enrollments" x
  where x."enrollment_id" = sequence_member_json.enrollment_id;
$$;
revoke execute on function "better_supabase"."sequence_member_json"(uuid) from public, anon, authenticated;

-- Moves a recipient to their first step not done: a wait step runs once its
-- minutes pass, the others right away. With every step done the run
-- completes. A recipient already on that step keeps their schedule.
create or replace function "better_supabase"."sequence_place"(enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
  v_steps jsonb;
  v_next jsonb;
begin
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_place.enrollment_id for update;
  if v_member."enrollment_id" is null or v_member."status" in ('completed', 'exited') then
    return;
  end if;
  select y."steps" into v_steps from "better_supabase"."sequences" y where y."id" = v_member."sequence_id";
  select t.value into v_next
  from jsonb_array_elements(coalesce(v_steps, '[]'::jsonb)) with ordinality as t(value, ord)
  where not exists (select 1 from "better_supabase"."enrollment_steps" z where z."enrollment_id" = v_member."enrollment_id" and z."step" = t.value ->> 'id')
  order by t.ord
  limit 1;
  if v_next is null then
    update "better_supabase"."sequence_enrollments" x
    set "status" = 'completed', "step" = null, "next_run_at" = null, "attempts" = 0, "last_error" = null, "updated_at" = now()
    where x."enrollment_id" = v_member."enrollment_id"
    returning * into v_member;
    perform "better_supabase".emit_event('sequence_enrollment.completed', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
    return;
  end if;
  if (v_next ->> 'id') is not distinct from v_member."step" then
    return;
  end if;
  update "better_supabase"."sequence_enrollments" x
  set "step" = v_next ->> 'id',
    "next_run_at" = case when v_next ->> 'kind' = 'wait' then now() + make_interval(mins => (v_next ->> 'minutes')::integer) else now() end,
    "attempts" = 0, "last_error" = null, "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id";
end;
$$;
revoke execute on function "better_supabase"."sequence_place"(uuid) from public, anon, authenticated;

-- Ends a recipient's run (reason: replied, manual, failed or archived) and
-- cancels their enrollment; the completed steps stay.
create or replace function "better_supabase"."sequence_exit"(enrollment_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  update "better_supabase"."sequence_enrollments" x
  set "status" = 'exited', "exit_reason" = sequence_exit.reason, "next_run_at" = null, "updated_at" = now()
  where x."enrollment_id" = sequence_exit.enrollment_id and x."status" in ('active', 'paused')
  returning * into v_member;
  if v_member."enrollment_id" is null then
    return;
  end if;
  update "better_supabase"."enrollments" x
  set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
  where x."id" = v_member."enrollment_id" and x."status" <> 'cancelled';
  if sequence_exit.reason = 'manual' then
    perform "better_supabase".emit_event('sequence_enrollment.exited', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', v_member."exit_reason"), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence_enrollment.exited',
    category => 'data',
    target_type => 'sequence',
    record_id => v_member."sequence_id"::text,
    target_label => v_member."subject_type" || ':' || v_member."subject_id",
    summary => 'removed from a sequence',
    tenant => (v_member."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', v_member."exit_reason")
  );
  else
    perform "better_supabase".emit_event('sequence_enrollment.exited', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', v_member."exit_reason"), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
  end if;
end;
$$;
revoke execute on function "better_supabase"."sequence_exit"(uuid, text) from public, anon, authenticated;

-- Marks the recipient's current step done and moves them on.
create or replace function "better_supabase"."sequence_step_done"(enrollment_id uuid, step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  perform "better_supabase"."enrollment_mark"(sequence_step_done.enrollment_id, sequence_step_done.step, true, null);
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_done.enrollment_id;
  perform "better_supabase".emit_event('sequence_enrollment.step_completed', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', sequence_step_done.step, 'reason', null::text), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
  perform "better_supabase"."sequence_place"(sequence_step_done.enrollment_id);
end;
$$;
revoke execute on function "better_supabase"."sequence_step_done"(uuid, text) from public, anon, authenticated;

-- Gives every running recipient of a sequence its current steps and moves
-- them to their first step not done.
create or replace function "better_supabase"."sequence_resync"(sequence_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "better_supabase"."sequences";
  v_member "better_supabase"."sequence_enrollments";
begin
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = sequence_resync.sequence_id;
  for v_member in
    select * from "better_supabase"."sequence_enrollments" x
    where x."sequence_id" = sequence_resync.sequence_id and x."status" in ('active', 'paused')
    for update
  loop
    perform "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
      v_member."subject_type", v_member."subject_id", null);
    perform "better_supabase"."sequence_place"(v_member."enrollment_id");
  end loop;
end;
$$;
revoke execute on function "better_supabase"."sequence_resync"(uuid) from public, anon, authenticated;

-- Creates or changes a sequence. sequence is { id?, key, name,
-- description, status, exitOnReply, accountId, steps }; keys left out keep
-- their value. Changing the steps raises the version and moves running
-- recipients onto the new steps. Archiving ends every run.
create or replace function "better_supabase"."save_sequence"(tenant uuid, sequence jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."sequences";
  v_row "better_supabase"."sequences";
  v_key text;
  v_name text;
  v_description text;
  v_status text;
  v_exit boolean;
  v_account uuid;
  v_steps jsonb;
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_sequence.tenant is not null and coalesce(better_supabase.can('tenant', save_sequence.tenant, 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if save_sequence.sequence is null or jsonb_typeof(save_sequence.sequence) <> 'object' then
    raise exception 'sequence must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_id := nullif(save_sequence.sequence ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."sequences" x
    where x."id" = v_id and x."tenant_id" = save_sequence.tenant
    for update;
    if v_old."id" is null then
      raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_sequence.sequence ->> 'key', v_old."key");
  v_name := trim(coalesce(save_sequence.sequence ->> 'name', v_old."name"));
  v_description := case when save_sequence.sequence ? 'description'
    then nullif(trim(save_sequence.sequence ->> 'description'), '') else v_old."description" end;
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old."status", 'draft');
  v_exit := case when save_sequence.sequence ? 'exitOnReply'
    then (save_sequence.sequence ->> 'exitOnReply')::boolean else coalesce(v_old."exit_on_reply", true) end;
  v_account := case when save_sequence.sequence ? 'accountId'
    then nullif(save_sequence.sequence ->> 'accountId', '')::uuid else v_old."mail_account_id" end;
  v_steps := case when save_sequence.sequence ? 'steps'
    then save_sequence.sequence -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a sequence''s key can''t change' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'status must be draft, active, paused or archived' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_exit is null then
    raise exception 'exitOnReply must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  perform "better_supabase"."sequence_steps_check"(v_steps, true);
  if v_status = 'active' and jsonb_array_length(v_steps) = 0 then
    raise exception 'an active sequence needs at least one step' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null and not exists (
    select 1 from "better_supabase"."mail_accounts" k
    where k."id" = v_account and k."tenant_id" = save_sequence.tenant
      and k."status" <> 'disconnected'
  ) then
    raise exception 'accountId must be a connected mailbox of this organization' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."sequences" ("tenant_id", "key", "name", "description", "status", "exit_on_reply", "mail_account_id", "steps", "created_by")
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."sequences" x
    set "name" = v_name, "description" = v_description, "status" = v_status, "exit_on_reply" = v_exit,
      "mail_account_id" = v_account, "steps" = v_steps,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
    if v_old."steps" is distinct from v_row."steps" then
      perform "better_supabase"."sequence_resync"(v_row."id");
    end if;
    if v_row."status" = 'archived' and v_old."status" <> 'archived' then
      for v_member in
        select * from "better_supabase"."sequence_enrollments" x
        where x."sequence_id" = v_row."id" and x."status" in ('active', 'paused')
      loop
        perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'archived');
      end loop;
    end if;
  end if;
  perform "better_supabase".emit_event('sequence.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.saved',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'saved a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."save_sequence"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_sequence"(uuid, jsonb) to authenticated, service_role;

-- An organization's sequences with their recipient counts, by name. status
-- filters; without it archived sequences stay out.
create or replace function "better_supabase"."list_sequences"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequences.tenant is not null and coalesce(better_supabase.can('tenant', list_sequences.tenant, 'sequences.read'), false))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = x."id")) order by x."name", x."id")
    from "better_supabase"."sequences" x
    where x."tenant_id" = list_sequences.tenant
      and (case when list_sequences.status is null then x."status" <> 'archived' else x."status" = list_sequences.status end)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_sequences"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_sequences"(uuid, text) to authenticated, service_role;

-- One sequence with its recipient counts.
create or replace function "better_supabase"."get_sequence"(sequence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."sequences";
begin
  select * into v_row from "better_supabase"."sequences" x where x."id" = get_sequence.sequence_id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.read'), false))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_sequence"(uuid) from public, anon;
grant execute on function "better_supabase"."get_sequence"(uuid) to authenticated, service_role;

-- Deletes a sequence with its enrollments; false when there was none.
create or replace function "better_supabase"."delete_sequence"(sequence_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."sequences";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."sequences" x where x."id" = delete_sequence.sequence_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = ('sequence:' || v_row."id"::text);
  delete from "better_supabase"."sequences" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('sequence.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.deleted',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'deleted a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_sequence"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_sequence"(uuid) to authenticated, service_role;

-- Enrolls a record (subject_type, subject_id) in an active sequence. attrs
-- is { address, name, accountId, variables }: a person's email and name fill
-- address and name when left out, and the mailbox defaults to the
-- sequence's, then the caller's. A finished or exited run starts over.
create or replace function "better_supabase"."enroll_in_sequence"(sequence_id uuid, subject_type text, subject_id text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "better_supabase"."sequences";
  v_row "better_supabase"."enrollments";
  v_member "better_supabase"."sequence_enrollments";
  v_attrs jsonb := coalesce(enroll_in_sequence.attrs, '{}'::jsonb);
  v_address text;
  v_name text;
  v_email text;
  v_label text;
  v_account uuid;
  v_owner uuid;
  v_variables jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = enroll_in_sequence.sequence_id;
  if v_sequence."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to enroll in sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if v_sequence."status" <> 'active' then
    raise exception 'only an active sequence takes enrollments' using errcode = '55000', hint = 'SEQUENCE_NOT_ACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_type is null or enroll_in_sequence.subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'subject_type: use lowercase letters, digits or _' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_id is null or length(enroll_in_sequence.subject_id) not between 1 and 200 then
    raise exception 'subject_id must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_address := nullif(trim(v_attrs ->> 'address'), '');
  v_name := nullif(trim(v_attrs ->> 'name'), '');
  v_account := nullif(v_attrs ->> 'accountId', '')::uuid;
  v_variables := coalesce(v_attrs -> 'variables', '{}'::jsonb);
  if enroll_in_sequence.subject_type = 'person' then
    select y."email", y."name" into v_email, v_label
    from "better_supabase"."people" y
    where y."id"::text = enroll_in_sequence.subject_id and y."tenant_id" = v_sequence."tenant_id";
    if not found then
      raise exception 'no such person in this organization' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_address := coalesce(v_address, v_email);
    v_name := coalesce(v_name, v_label);
  end if;
  if v_address is not null and (length(v_address) > 320 or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$') then
    raise exception 'address must be an email address' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_name) > 200 then
    raise exception 'name must be at most 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_typeof(v_variables) <> 'object' or length(v_variables::text) > 10000 then
    raise exception 'variables must be an object of at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_address is null and exists (select 1 from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'kind' = 'email') then
    raise exception 'the recipient needs an email address for the sequence''s email steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is null then
    v_account := coalesce(v_sequence."mail_account_id", (
      select k."id" from "better_supabase"."mail_accounts" k
      where k."tenant_id" = v_sequence."tenant_id" and k."user_id" = auth.uid() and k."status" = 'active'
      order by k."created_at", k."id"
      limit 1));
  else
    select k."user_id" into v_owner from "better_supabase"."mail_accounts" k
    where k."id" = v_account and k."tenant_id" = v_sequence."tenant_id" and k."status" <> 'disconnected';
    if not found then
      raise exception 'accountId must be a connected mailbox of this organization' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    if v_owner is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.manage'), false))) then
      raise exception 'only a sequence manager sends from another user''s mailbox' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
    end if;
  end if;
  if v_account is null and exists (select 1 from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'kind' = 'email') then
    raise exception 'connect a mailbox or set one on the sequence to send its email steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_sequence."tenant_id" and x."program" = ('sequence:' || v_sequence."id"::text)
    and x."subject_type" = enroll_in_sequence.subject_type and x."subject_id" = enroll_in_sequence.subject_id
  for update;
  if v_row."id" is not null then
    select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_row."id" for update;
    if v_member."status" in ('active', 'paused') then
      return "better_supabase"."sequence_member_json"(v_row."id");
    end if;
    -- Starting over: clearing the steps makes enrollment_ensure take the
    -- current ones, with none done.
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id";
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "completed_at" = null, "enrolled_by" = auth.uid(),
      "enrolled_at" = now(), "steps" = '{}'
    where x."id" = v_row."id";
  end if;
  v_id := "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
    enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  insert into "better_supabase"."sequence_enrollments" ("enrollment_id", "tenant_id", "sequence_id", "subject_type", "subject_id", "address", "name",
    "mail_account_id", "variables", "enrolled_by")
  values (v_id, v_sequence."tenant_id", v_sequence."id", enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, v_address, v_name,
    v_account, v_variables, auth.uid())
  on conflict ("enrollment_id") do update
  set "address" = excluded."address", "name" = excluded."name", "mail_account_id" = excluded."mail_account_id",
    "variables" = excluded."variables", "enrolled_by" = excluded."enrolled_by", "status" = 'active',
    "exit_reason" = null, "step" = null, "next_run_at" = null, "mail_thread_id" = null, "attempts" = 0,
    "last_error" = null, "updated_at" = now();
  perform "better_supabase"."sequence_place"(v_id);
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_id;
  perform "better_supabase".emit_event('sequence_enrollment.created', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence_enrollment.created',
    category => 'data',
    target_type => 'sequence',
    record_id => v_member."sequence_id"::text,
    target_label => v_member."subject_type" || ':' || v_member."subject_id",
    summary => 'enrolled in a sequence',
    tenant => (v_member."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text)
  );
  return "better_supabase"."sequence_member_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll_in_sequence"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."enroll_in_sequence"(uuid, text, text, jsonb) to authenticated, service_role;

-- Pauses, resumes or exits a recipient's run (action: pause, resume, exit).
create or replace function "better_supabase"."change_sequence_enrollment"(enrollment_id uuid, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = change_sequence_enrollment.enrollment_id for update;
  if v_member."enrollment_id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to change sequence enrollments' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  case change_sequence_enrollment.action
    when 'pause' then
      if v_member."status" <> 'active' then
        raise exception 'only an active run can be paused' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "better_supabase"."sequence_enrollments" x set "status" = 'paused', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      perform "better_supabase".emit_event('sequence_enrollment.paused', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence_enrollment.paused',
    category => 'data',
    target_type => 'sequence',
    record_id => v_member."sequence_id"::text,
    target_label => v_member."subject_type" || ':' || v_member."subject_id",
    summary => 'paused a sequence run',
    tenant => (v_member."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text)
  );
    when 'resume' then
      if v_member."status" <> 'paused' then
        raise exception 'only a paused run can be resumed' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "better_supabase"."sequence_enrollments" x set "status" = 'active', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      perform "better_supabase".emit_event('sequence_enrollment.resumed', jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text), 'sequence-enrollments/' || v_member."enrollment_id"::text, (v_member."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence_enrollment.resumed',
    category => 'data',
    target_type => 'sequence',
    record_id => v_member."sequence_id"::text,
    target_label => v_member."subject_type" || ':' || v_member."subject_id",
    summary => 'resumed a sequence run',
    tenant => (v_member."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_member."tenant_id", 'id', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id", 'status', v_member."status", 'step', null::text, 'reason', null::text)
  );
    when 'exit' then
      if v_member."status" not in ('active', 'paused') then
        raise exception 'only an active or paused run can be exited' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'manual');
    else
      raise exception 'action must be pause, resume or exit' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end case;
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) from public, anon;
grant execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) to authenticated, service_role;

-- An organization's sequence recipients, newest first. filter is
-- { sequence, subjectType, subjectId, status, limit, before }: before is a
-- createdAt from the previous page.
create or replace function "better_supabase"."list_sequence_enrollments"(tenant uuid, filter jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_sequence_enrollments.filter, '{}'::jsonb);
  v_parent uuid := nullif(v_filter ->> 'sequence', '')::uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.enroll'), false)))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filter) <> 'object' then
    raise exception 'filter must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."sequence_member_json"(y."enrollment_id") order by y."created_at" desc, y."enrollment_id" desc)
    from (
      select x."enrollment_id", x."created_at"
      from "better_supabase"."sequence_enrollments" x
      where x."tenant_id" = list_sequence_enrollments.tenant
        and (v_parent is null or x."sequence_id" = v_parent)
        and (v_filter ->> 'subjectType' is null or x."subject_type" = v_filter ->> 'subjectType')
        and (v_filter ->> 'subjectId' is null or x."subject_id" = v_filter ->> 'subjectId')
        and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
        and (v_filter ->> 'before' is null or x."created_at" < (v_filter ->> 'before')::timestamptz)
      order by x."created_at" desc, x."enrollment_id" desc
      limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_sequence_enrollments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_sequence_enrollments"(uuid, jsonb) to authenticated, service_role;

-- Runs the steps that are due, oldest first: wait steps finish, task steps
-- create a work item for whoever enrolled the recipient, and email steps
-- are claimed for 10 minutes and returned for the caller to send. Call
-- sequence_step_sent or sequence_step_failed with each result. Returns
-- { ran, emails: [{ enrollmentId, sequenceId, organizationId, accountId,
-- threadId, to, step, variables, attempt, subjectType, subjectId }] }.
create or replace function "better_supabase"."run_due_sequences"(max_count integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_due "better_supabase"."sequence_enrollments";
  v_member "better_supabase"."sequence_enrollments";
  v_sequence "better_supabase"."sequences";
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  for v_due in
    select x.* from "better_supabase"."sequence_enrollments" x
    join "better_supabase"."sequences" y on y."id" = x."sequence_id"
    where x."status" = 'active' and x."next_run_at" <= now() and y."status" = 'active'
    order by x."next_run_at", x."enrollment_id"
    limit least(greatest(coalesce(run_due_sequences.max_count, 50), 1), 500)
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_due."enrollment_id";
      exit when v_member."status" <> 'active' or v_member."step" is null or v_member."next_run_at" > now();
      select * into v_sequence from "better_supabase"."sequences" x where x."id" = v_member."sequence_id";
      v_step := (select t.value from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'id' = v_member."step");
      if v_step is null then
        perform "better_supabase"."sequence_place"(v_member."enrollment_id");
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        update "better_supabase"."sequence_enrollments" x
        set "attempts" = x."attempts" + 1, "next_run_at" = now() + interval '10 minutes', "updated_at" = now()
        where x."enrollment_id" = v_member."enrollment_id"
        returning * into v_member;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'organizationId', v_member."tenant_id",
          'accountId', coalesce(v_member."mail_account_id", v_sequence."mail_account_id"), 'threadId', v_member."mail_thread_id",
          'to', jsonb_build_object('address', v_member."address", 'name', v_member."name"),
          'step', v_step, 'variables', v_member."variables", 'attempt', v_member."attempts",
          'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id"));
        exit;
      end if;
      if v_step ->> 'kind' = 'task' then
        perform "better_supabase"."create_work_item"(v_member."tenant_id", jsonb_build_object(
          'title', trim(v_step ->> 'title'),
          'body', v_step ->> 'body',
          'dueAt', case when v_step ? 'dueInMinutes' then now() + make_interval(mins => (v_step ->> 'dueInMinutes')::integer) end),
          case when v_member."enrolled_by" is null then '{}'::uuid[] else array[v_member."enrolled_by"] end);
      end if;
      perform "better_supabase"."sequence_step_done"(v_member."enrollment_id", v_member."step");
      v_ran := v_ran + 1;
    end loop;
  end loop;
  return jsonb_build_object('ran', v_ran, 'emails', v_emails);
end;
$$;
revoke execute on function "better_supabase"."run_due_sequences"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."run_due_sequences"(integer) to service_role;

-- Records that a claimed email step went out as message_id (a mail-sync
-- message, or null): later emails reply on its thread. A stale result, for
-- a run that moved on, changes nothing.
create or replace function "better_supabase"."sequence_step_sent"(enrollment_id uuid, step text, message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_sent.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_sent.step then
    return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
  end if;
  if sequence_step_sent.message_id is not null then
    update "better_supabase"."sequence_enrollments" x
    set "mail_thread_id" = coalesce(x."mail_thread_id", y."thread_id"), "mail_account_id" = coalesce(x."mail_account_id", y."account_id"), "updated_at" = now()
    from "better_supabase"."mail_messages" y
    where x."enrollment_id" = v_member."enrollment_id" and y."id" = sequence_step_sent.message_id and y."tenant_id" = v_member."tenant_id";
  end if;
  perform "better_supabase"."sequence_step_done"(v_member."enrollment_id", sequence_step_sent.step);
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."sequence_step_sent"(uuid, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."sequence_step_sent"(uuid, text, uuid) to service_role;

-- Records that a claimed email step failed to send: it runs again after
-- 15 minutes times the attempts, and the run exits as failed after
-- 3 attempts.
create or replace function "better_supabase"."sequence_step_failed"(enrollment_id uuid, step text, error text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_failed.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_failed.step then
    return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
  end if;
  update "better_supabase"."sequence_enrollments" x
  set "last_error" = left(coalesce(sequence_step_failed.error, 'send failed'), 2000),
    "next_run_at" = now() + make_interval(mins => 15 * greatest(x."attempts", 1)),
    "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id"
  returning * into v_member;
  if v_member."attempts" >= 3 then
    perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'failed');
  end if;
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."sequence_step_failed"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sequence_step_failed"(uuid, text, text) to service_role;

-- An inbound message on a recipient's thread, or from their address, ends
-- their run in every sequence that exits on reply.
create or replace function "better_supabase"."sequence_mail_replied"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  for v_member in
    select x.* from "better_supabase"."sequence_enrollments" x
    join "better_supabase"."sequences" y on y."id" = x."sequence_id"
    where x."tenant_id" = new."tenant_id" and x."status" in ('active', 'paused') and y."exit_on_reply"
      and ((new."thread_id" is not null and x."mail_thread_id" = new."thread_id")
        or (new."from_address" is not null and lower(x."address") = lower(new."from_address")))
    for update of x
  loop
    perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'replied');
  end loop;
  return null;
end;
$$;
revoke execute on function "better_supabase"."sequence_mail_replied"() from public, anon, authenticated;
drop trigger if exists "bsb_replied" on "better_supabase"."mail_messages";
create trigger "bsb_replied"
  after insert on "better_supabase"."mail_messages"
  for each row when (new."direction" = 'inbound')
  execute function "better_supabase"."sequence_mail_replied"();

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block-data sequences
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sequences', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block sequences@1 managed
-- Multi-step outreach sequences whose steps send email through mail-sync, create work items or wait. Each sequence runs as an enrollment program, and a reply on the thread or from the recipient's address ends their run.
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
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Outreach sequences: steps that send email, create a task or wait. Each
-- sequence runs as the enrollment program sequence:<id>, whose steps are the
-- sequence's steps; a reply ends a recipient's run.
create table if not exists "app_private"."sequences" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'active', 'paused', 'archived')),
  -- An inbound message on the thread, or from the recipient's address, ends
  -- the recipient's run.
  "exit_on_reply" boolean not null default true,
  -- The mailbox email steps send from when the enrollment names none.
  "mail_account_id" uuid,
  -- The steps in order: [{ id, kind: email | task | wait, ... }]. Each is a
  -- step of the enrollment program sequence:<id>.
  "steps" jsonb not null default '[]' check (jsonb_typeof("steps") = 'array'),
  "version" integer not null default 1 check ("version" >= 1),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint "sequences_key_key" unique ("tenant_id", "key")
);
create index if not exists "sequences_account_idx" on "app_private"."sequences" ("mail_account_id") where "mail_account_id" is not null;

-- Where a recipient is in a sequence. The enrollment holds the completed
-- steps; this holds the next step, when it runs and who it goes to.
create table if not exists "app_private"."sequence_enrollments" (
  "enrollment_id" uuid primary key references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "sequence_id" uuid not null references "app_private"."sequences" ("id") on delete cascade,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "address" text check ("address" is null or (length("address") <= 320 and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  "name" text check ("name" is null or length("name") <= 200),
  "mail_account_id" uuid,
  -- The thread the first email started; later emails reply on it.
  "mail_thread_id" uuid,
  -- The step that runs next, null once every step is done.
  "step" text,
  "next_run_at" timestamptz,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'completed', 'exited')),
  "exit_reason" text check ("exit_reason" is null or "exit_reason" in ('replied', 'manual', 'failed', 'archived')),
  "attempts" integer not null default 0 check ("attempts" >= 0),
  "last_error" text check ("last_error" is null or length("last_error") <= 2000),
  -- Values for the {{key}} placeholders of the email steps.
  "variables" jsonb not null default '{}' check (jsonb_typeof("variables") = 'object'),
  "enrolled_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("status" = 'exited') = ("exit_reason" is not null))
);
create index if not exists "sequence_enrollments_parent_idx" on "app_private"."sequence_enrollments" ("sequence_id", "status");
create index if not exists "sequence_enrollments_due_idx" on "app_private"."sequence_enrollments" ("next_run_at") where "status" = 'active';
create index if not exists "sequence_enrollments_subject_idx" on "app_private"."sequence_enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "sequence_enrollments_address_idx" on "app_private"."sequence_enrollments" ("tenant_id", lower("address")) where "status" in ('active', 'paused');
create index if not exists "sequence_enrollments_account_idx" on "app_private"."sequence_enrollments" ("mail_account_id") where "mail_account_id" is not null;
create index if not exists "sequence_enrollments_thread_idx" on "app_private"."sequence_enrollments" ("mail_thread_id") where "mail_thread_id" is not null;

alter table "app_private"."sequences" enable row level security;
revoke all on "app_private"."sequences" from anon, authenticated;
grant select on "app_private"."sequences" to authenticated;
grant all on "app_private"."sequences" to service_role;
drop policy if exists "sequences_read" on "app_private"."sequences";
create policy "sequences_read" on "app_private"."sequences" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));
alter table "app_private"."sequence_enrollments" enable row level security;
revoke all on "app_private"."sequence_enrollments" from anon, authenticated;
grant select on "app_private"."sequence_enrollments" to authenticated;
grant all on "app_private"."sequence_enrollments" to service_role;
drop policy if exists "sequence_enrollments_read" on "app_private"."sequence_enrollments";
create policy "sequence_enrollments_read" on "app_private"."sequence_enrollments" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));

-- Checks a steps array: [{ id, kind, ... }] where an email step has a
-- subject and text or html, a task step a title, and a wait step minutes.
create or replace function "app_private"."sequence_steps_check"(steps jsonb, mail boolean)
returns void
language plpgsql
immutable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_step jsonb;
  v_ids text[] := '{}';
  v_id text;
begin
  if sequence_steps_check.steps is null or jsonb_typeof(sequence_steps_check.steps) <> 'array' then
    raise exception 'steps must be an array' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_array_length(sequence_steps_check.steps) > 50 then
    raise exception 'a sequence has at most 50 steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(sequence_steps_check.steps) t loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'each step must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_id := v_step ->> 'id';
    if v_id is null or v_id !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
      raise exception 'step id: use lowercase letters, digits, "_" or "-"' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    if v_id = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_ids := v_ids || v_id;
    case v_step ->> 'kind'
      when 'wait' then
        if jsonb_typeof(v_step -> 'minutes') is distinct from 'number'
          or (v_step ->> 'minutes')::numeric <> trunc((v_step ->> 'minutes')::numeric)
          or (v_step ->> 'minutes')::numeric not between 1 and 525600 then
          raise exception 'a wait step waits 1 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'email' then
        if not sequence_steps_check.mail then
          raise exception 'email steps need the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(trim(v_step ->> 'subject'), '')) not between 1 and 300 then
          raise exception 'an email step needs a subject of 1 to 300 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if coalesce(v_step ->> 'text', v_step ->> 'html') is null then
          raise exception 'an email step needs text or html' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'text', '')) + length(coalesce(v_step ->> 'html', '')) > 200000 then
          raise exception 'an email step''s body is at most 200000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'track' and jsonb_typeof(v_step -> 'track') <> 'boolean' then
          raise exception 'track must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'templateVersionId' and coalesce(v_step ->> 'templateVersionId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          raise exception 'templateVersionId must be a uuid' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'task' then
        if length(coalesce(trim(v_step ->> 'title'), '')) not between 1 and 200 then
          raise exception 'a task step needs a title of 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'body', '')) > 10000 then
          raise exception 'a task step''s body is at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'dueInMinutes' and (jsonb_typeof(v_step -> 'dueInMinutes') is distinct from 'number'
          or (v_step ->> 'dueInMinutes')::numeric <> trunc((v_step ->> 'dueInMinutes')::numeric)
          or (v_step ->> 'dueInMinutes')::numeric not between 0 and 525600) then
          raise exception 'dueInMinutes must be 0 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      else
        raise exception 'a step''s kind must be email, task or wait' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end case;
  end loop;
end;
$$;
revoke execute on function "app_private"."sequence_steps_check"(jsonb, boolean) from public, anon, authenticated;

-- A recipient in a sequence with their completed steps.
create or replace function "app_private"."sequence_member_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."enrollment_id", 'organizationId', x."tenant_id", 'sequenceId', x."sequence_id",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'name', x."name",
    'accountId', x."mail_account_id", 'threadId', x."mail_thread_id", 'step', x."step", 'nextRunAt', x."next_run_at",
    'status', x."status", 'exitReason', x."exit_reason", 'attempts', x."attempts", 'lastError', x."last_error",
    'variables', x."variables", 'enrolledBy', x."enrolled_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
    'completedSteps', coalesce((select jsonb_agg(y."step" order by y."completed_at", y."step") from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."enrollment_id"), '[]'::jsonb))
  from "app_private"."sequence_enrollments" x
  where x."enrollment_id" = sequence_member_json.enrollment_id;
$$;
revoke execute on function "app_private"."sequence_member_json"(uuid) from public, anon, authenticated;

-- Moves a recipient to their first step not done: a wait step runs once its
-- minutes pass, the others right away. With every step done the run
-- completes. A recipient already on that step keeps their schedule.
create or replace function "app_private"."sequence_place"(enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "app_private"."sequence_enrollments";
  v_steps jsonb;
  v_next jsonb;
begin
  select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = sequence_place.enrollment_id for update;
  if v_member."enrollment_id" is null or v_member."status" in ('completed', 'exited') then
    return;
  end if;
  select y."steps" into v_steps from "app_private"."sequences" y where y."id" = v_member."sequence_id";
  select t.value into v_next
  from jsonb_array_elements(coalesce(v_steps, '[]'::jsonb)) with ordinality as t(value, ord)
  where not exists (select 1 from "better_supabase"."enrollment_steps" z where z."enrollment_id" = v_member."enrollment_id" and z."step" = t.value ->> 'id')
  order by t.ord
  limit 1;
  if v_next is null then
    update "app_private"."sequence_enrollments" x
    set "status" = 'completed', "step" = null, "next_run_at" = null, "attempts" = 0, "last_error" = null, "updated_at" = now()
    where x."enrollment_id" = v_member."enrollment_id"
    returning * into v_member;
    null;
    return;
  end if;
  if (v_next ->> 'id') is not distinct from v_member."step" then
    return;
  end if;
  update "app_private"."sequence_enrollments" x
  set "step" = v_next ->> 'id',
    "next_run_at" = case when v_next ->> 'kind' = 'wait' then now() + make_interval(mins => (v_next ->> 'minutes')::integer) else now() end,
    "attempts" = 0, "last_error" = null, "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id";
end;
$$;
revoke execute on function "app_private"."sequence_place"(uuid) from public, anon, authenticated;

-- Ends a recipient's run (reason: replied, manual, failed or archived) and
-- cancels their enrollment; the completed steps stay.
create or replace function "app_private"."sequence_exit"(enrollment_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "app_private"."sequence_enrollments";
begin
  update "app_private"."sequence_enrollments" x
  set "status" = 'exited', "exit_reason" = sequence_exit.reason, "next_run_at" = null, "updated_at" = now()
  where x."enrollment_id" = sequence_exit.enrollment_id and x."status" in ('active', 'paused')
  returning * into v_member;
  if v_member."enrollment_id" is null then
    return;
  end if;
  update "better_supabase"."enrollments" x
  set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
  where x."id" = v_member."enrollment_id" and x."status" <> 'cancelled';
  if sequence_exit.reason = 'manual' then
    null;
  else
    null;
  end if;
end;
$$;
revoke execute on function "app_private"."sequence_exit"(uuid, text) from public, anon, authenticated;

-- Marks the recipient's current step done and moves them on.
create or replace function "app_private"."sequence_step_done"(enrollment_id uuid, step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "app_private"."sequence_enrollments";
begin
  perform "app_private"."enrollment_mark"(sequence_step_done.enrollment_id, sequence_step_done.step, true, null);
  select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = sequence_step_done.enrollment_id;
  null;
  perform "app_private"."sequence_place"(sequence_step_done.enrollment_id);
end;
$$;
revoke execute on function "app_private"."sequence_step_done"(uuid, text) from public, anon, authenticated;

-- Gives every running recipient of a sequence its current steps and moves
-- them to their first step not done.
create or replace function "app_private"."sequence_resync"(sequence_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "app_private"."sequences";
  v_member "app_private"."sequence_enrollments";
begin
  select * into v_sequence from "app_private"."sequences" x where x."id" = sequence_resync.sequence_id;
  for v_member in
    select * from "app_private"."sequence_enrollments" x
    where x."sequence_id" = sequence_resync.sequence_id and x."status" in ('active', 'paused')
    for update
  loop
    perform "app_private"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
      v_member."subject_type", v_member."subject_id", null);
    perform "app_private"."sequence_place"(v_member."enrollment_id");
  end loop;
end;
$$;
revoke execute on function "app_private"."sequence_resync"(uuid) from public, anon, authenticated;

-- Creates or changes a sequence. sequence is { id?, key, name,
-- description, status, exitOnReply, accountId, steps }; keys left out keep
-- their value. Changing the steps raises the version and moves running
-- recipients onto the new steps. Archiving ends every run.
create or replace function "app_private"."save_sequence"(tenant uuid, sequence jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "app_private"."sequences";
  v_row "app_private"."sequences";
  v_key text;
  v_name text;
  v_description text;
  v_status text;
  v_exit boolean;
  v_account uuid;
  v_steps jsonb;
  v_member "app_private"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_sequence.tenant is not null and coalesce(better_supabase.can('tenant', save_sequence.tenant, 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if save_sequence.sequence is null or jsonb_typeof(save_sequence.sequence) <> 'object' then
    raise exception 'sequence must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_id := nullif(save_sequence.sequence ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "app_private"."sequences" x
    where x."id" = v_id and x."tenant_id" = save_sequence.tenant
    for update;
    if v_old."id" is null then
      raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_sequence.sequence ->> 'key', v_old."key");
  v_name := trim(coalesce(save_sequence.sequence ->> 'name', v_old."name"));
  v_description := case when save_sequence.sequence ? 'description'
    then nullif(trim(save_sequence.sequence ->> 'description'), '') else v_old."description" end;
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old."status", 'draft');
  v_exit := case when save_sequence.sequence ? 'exitOnReply'
    then (save_sequence.sequence ->> 'exitOnReply')::boolean else coalesce(v_old."exit_on_reply", true) end;
  v_account := case when save_sequence.sequence ? 'accountId'
    then nullif(save_sequence.sequence ->> 'accountId', '')::uuid else v_old."mail_account_id" end;
  v_steps := case when save_sequence.sequence ? 'steps'
    then save_sequence.sequence -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a sequence''s key can''t change' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'status must be draft, active, paused or archived' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_exit is null then
    raise exception 'exitOnReply must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  perform "app_private"."sequence_steps_check"(v_steps, false);
  if v_status = 'active' and jsonb_array_length(v_steps) = 0 then
    raise exception 'an active sequence needs at least one step' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null then
    raise exception 'accountId needs the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "app_private"."sequences" ("tenant_id", "key", "name", "description", "status", "exit_on_reply", "mail_account_id", "steps", "created_by")
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, auth.uid())
    returning * into v_row;
  else
    update "app_private"."sequences" x
    set "name" = v_name, "description" = v_description, "status" = v_status, "exit_on_reply" = v_exit,
      "mail_account_id" = v_account, "steps" = v_steps,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
    if v_old."steps" is distinct from v_row."steps" then
      perform "app_private"."sequence_resync"(v_row."id");
    end if;
    if v_row."status" = 'archived' and v_old."status" <> 'archived' then
      for v_member in
        select * from "app_private"."sequence_enrollments" x
        where x."sequence_id" = v_row."id" and x."status" in ('active', 'paused')
      loop
        perform "app_private"."sequence_exit"(v_member."enrollment_id", 'archived');
      end loop;
    end if;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "app_private"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."save_sequence"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_sequence"(uuid, jsonb) to authenticated, service_role;

-- An organization's sequences with their recipient counts, by name. status
-- filters; without it archived sequences stay out.
create or replace function "app_private"."list_sequences"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequences.tenant is not null and coalesce(better_supabase.can('tenant', list_sequences.tenant, 'sequences.read'), false))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "app_private"."sequence_enrollments" m where m."sequence_id" = x."id")) order by x."name", x."id")
    from "app_private"."sequences" x
    where x."tenant_id" = list_sequences.tenant
      and (case when list_sequences.status is null then x."status" <> 'archived' else x."status" = list_sequences.status end)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_sequences"(uuid, text) from public, anon;
grant execute on function "app_private"."list_sequences"(uuid, text) to authenticated, service_role;

-- One sequence with its recipient counts.
create or replace function "app_private"."get_sequence"(sequence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."sequences";
begin
  select * into v_row from "app_private"."sequences" x where x."id" = get_sequence.sequence_id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.read'), false))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "app_private"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "app_private"."get_sequence"(uuid) from public, anon;
grant execute on function "app_private"."get_sequence"(uuid) to authenticated, service_role;

-- Deletes a sequence with its enrollments; false when there was none.
create or replace function "app_private"."delete_sequence"(sequence_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "app_private"."sequences";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."sequences" x where x."id" = delete_sequence.sequence_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = ('sequence:' || v_row."id"::text);
  delete from "app_private"."sequences" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_sequence"(uuid) from public, anon;
grant execute on function "app_private"."delete_sequence"(uuid) to authenticated, service_role;

-- Enrolls a record (subject_type, subject_id) in an active sequence. attrs
-- is { address, name, accountId, variables }: a person's email and name fill
-- address and name when left out, and the mailbox defaults to the
-- sequence's, then the caller's. A finished or exited run starts over.
create or replace function "app_private"."enroll_in_sequence"(sequence_id uuid, subject_type text, subject_id text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "app_private"."sequences";
  v_row "better_supabase"."enrollments";
  v_member "app_private"."sequence_enrollments";
  v_attrs jsonb := coalesce(enroll_in_sequence.attrs, '{}'::jsonb);
  v_address text;
  v_name text;
  v_email text;
  v_label text;
  v_account uuid;
  v_owner uuid;
  v_variables jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sequence from "app_private"."sequences" x where x."id" = enroll_in_sequence.sequence_id;
  if v_sequence."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to enroll in sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if v_sequence."status" <> 'active' then
    raise exception 'only an active sequence takes enrollments' using errcode = '55000', hint = 'SEQUENCE_NOT_ACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_type is null or enroll_in_sequence.subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'subject_type: use lowercase letters, digits or _' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_id is null or length(enroll_in_sequence.subject_id) not between 1 and 200 then
    raise exception 'subject_id must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_address := nullif(trim(v_attrs ->> 'address'), '');
  v_name := nullif(trim(v_attrs ->> 'name'), '');
  v_account := nullif(v_attrs ->> 'accountId', '')::uuid;
  v_variables := coalesce(v_attrs -> 'variables', '{}'::jsonb);
  
  if v_address is not null and (length(v_address) > 320 or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$') then
    raise exception 'address must be an email address' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_name) > 200 then
    raise exception 'name must be at most 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_typeof(v_variables) <> 'object' or length(v_variables::text) > 10000 then
    raise exception 'variables must be an object of at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_address is null and exists (select 1 from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'kind' = 'email') then
    raise exception 'the recipient needs an email address for the sequence''s email steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null then
    raise exception 'accountId needs the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_sequence."tenant_id" and x."program" = ('sequence:' || v_sequence."id"::text)
    and x."subject_type" = enroll_in_sequence.subject_type and x."subject_id" = enroll_in_sequence.subject_id
  for update;
  if v_row."id" is not null then
    select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = v_row."id" for update;
    if v_member."status" in ('active', 'paused') then
      return "app_private"."sequence_member_json"(v_row."id");
    end if;
    -- Starting over: clearing the steps makes enrollment_ensure take the
    -- current ones, with none done.
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id";
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "completed_at" = null, "enrolled_by" = auth.uid(),
      "enrolled_at" = now(), "steps" = '{}'
    where x."id" = v_row."id";
  end if;
  v_id := "app_private"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
    enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  insert into "app_private"."sequence_enrollments" ("enrollment_id", "tenant_id", "sequence_id", "subject_type", "subject_id", "address", "name",
    "mail_account_id", "variables", "enrolled_by")
  values (v_id, v_sequence."tenant_id", v_sequence."id", enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, v_address, v_name,
    v_account, v_variables, auth.uid())
  on conflict ("enrollment_id") do update
  set "address" = excluded."address", "name" = excluded."name", "mail_account_id" = excluded."mail_account_id",
    "variables" = excluded."variables", "enrolled_by" = excluded."enrolled_by", "status" = 'active',
    "exit_reason" = null, "step" = null, "next_run_at" = null, "mail_thread_id" = null, "attempts" = 0,
    "last_error" = null, "updated_at" = now();
  perform "app_private"."sequence_place"(v_id);
  select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = v_id;
  null;
  return "app_private"."sequence_member_json"(v_id);
end;
$$;
revoke execute on function "app_private"."enroll_in_sequence"(uuid, text, text, jsonb) from public, anon;
grant execute on function "app_private"."enroll_in_sequence"(uuid, text, text, jsonb) to authenticated, service_role;

-- Pauses, resumes or exits a recipient's run (action: pause, resume, exit).
create or replace function "app_private"."change_sequence_enrollment"(enrollment_id uuid, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "app_private"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = change_sequence_enrollment.enrollment_id for update;
  if v_member."enrollment_id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to change sequence enrollments' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  case change_sequence_enrollment.action
    when 'pause' then
      if v_member."status" <> 'active' then
        raise exception 'only an active run can be paused' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "app_private"."sequence_enrollments" x set "status" = 'paused', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      null;
    when 'resume' then
      if v_member."status" <> 'paused' then
        raise exception 'only a paused run can be resumed' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "app_private"."sequence_enrollments" x set "status" = 'active', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      null;
    when 'exit' then
      if v_member."status" not in ('active', 'paused') then
        raise exception 'only an active or paused run can be exited' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      perform "app_private"."sequence_exit"(v_member."enrollment_id", 'manual');
    else
      raise exception 'action must be pause, resume or exit' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end case;
  return "app_private"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "app_private"."change_sequence_enrollment"(uuid, text) from public, anon;
grant execute on function "app_private"."change_sequence_enrollment"(uuid, text) to authenticated, service_role;

-- An organization's sequence recipients, newest first. filter is
-- { sequence, subjectType, subjectId, status, limit, before }: before is a
-- createdAt from the previous page.
create or replace function "app_private"."list_sequence_enrollments"(tenant uuid, filter jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_sequence_enrollments.filter, '{}'::jsonb);
  v_parent uuid := nullif(v_filter ->> 'sequence', '')::uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.enroll'), false)))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filter) <> 'object' then
    raise exception 'filter must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("app_private"."sequence_member_json"(y."enrollment_id") order by y."created_at" desc, y."enrollment_id" desc)
    from (
      select x."enrollment_id", x."created_at"
      from "app_private"."sequence_enrollments" x
      where x."tenant_id" = list_sequence_enrollments.tenant
        and (v_parent is null or x."sequence_id" = v_parent)
        and (v_filter ->> 'subjectType' is null or x."subject_type" = v_filter ->> 'subjectType')
        and (v_filter ->> 'subjectId' is null or x."subject_id" = v_filter ->> 'subjectId')
        and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
        and (v_filter ->> 'before' is null or x."created_at" < (v_filter ->> 'before')::timestamptz)
      order by x."created_at" desc, x."enrollment_id" desc
      limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_sequence_enrollments"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_sequence_enrollments"(uuid, jsonb) to authenticated, service_role;

-- Runs the steps that are due, oldest first: wait steps finish, task steps
-- create a work item for whoever enrolled the recipient, and email steps
-- are claimed for 10 minutes and returned for the caller to send. Call
-- sequence_step_sent or sequence_step_failed with each result. Returns
-- { ran, emails: [{ enrollmentId, sequenceId, organizationId, accountId,
-- threadId, to, step, variables, attempt, subjectType, subjectId }] }.
create or replace function "app_private"."run_due_sequences"(max_count integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_due "app_private"."sequence_enrollments";
  v_member "app_private"."sequence_enrollments";
  v_sequence "app_private"."sequences";
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  for v_due in
    select x.* from "app_private"."sequence_enrollments" x
    join "app_private"."sequences" y on y."id" = x."sequence_id"
    where x."status" = 'active' and x."next_run_at" <= now() and y."status" = 'active'
    order by x."next_run_at", x."enrollment_id"
    limit least(greatest(coalesce(run_due_sequences.max_count, 50), 1), 500)
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = v_due."enrollment_id";
      exit when v_member."status" <> 'active' or v_member."step" is null or v_member."next_run_at" > now();
      select * into v_sequence from "app_private"."sequences" x where x."id" = v_member."sequence_id";
      v_step := (select t.value from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'id' = v_member."step");
      if v_step is null then
        perform "app_private"."sequence_place"(v_member."enrollment_id");
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        update "app_private"."sequence_enrollments" x
        set "attempts" = x."attempts" + 1, "next_run_at" = now() + interval '10 minutes', "updated_at" = now()
        where x."enrollment_id" = v_member."enrollment_id"
        returning * into v_member;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'organizationId', v_member."tenant_id",
          'accountId', coalesce(v_member."mail_account_id", v_sequence."mail_account_id"), 'threadId', v_member."mail_thread_id",
          'to', jsonb_build_object('address', v_member."address", 'name', v_member."name"),
          'step', v_step, 'variables', v_member."variables", 'attempt', v_member."attempts",
          'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id"));
        exit;
      end if;
      perform "app_private"."sequence_step_done"(v_member."enrollment_id", v_member."step");
      v_ran := v_ran + 1;
    end loop;
  end loop;
  return jsonb_build_object('ran', v_ran, 'emails', v_emails);
end;
$$;
revoke execute on function "app_private"."run_due_sequences"(integer) from public, anon, authenticated;
grant execute on function "app_private"."run_due_sequences"(integer) to service_role;

-- Records that a claimed email step went out as message_id (a mail-sync
-- message, or null): later emails reply on its thread. A stale result, for
-- a run that moved on, changes nothing.
create or replace function "app_private"."sequence_step_sent"(enrollment_id uuid, step text, message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "app_private"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = sequence_step_sent.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_sent.step then
    return "app_private"."sequence_member_json"(v_member."enrollment_id");
  end if;
  perform "app_private"."sequence_step_done"(v_member."enrollment_id", sequence_step_sent.step);
  return "app_private"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "app_private"."sequence_step_sent"(uuid, text, uuid) from public, anon, authenticated;
grant execute on function "app_private"."sequence_step_sent"(uuid, text, uuid) to service_role;

-- Records that a claimed email step failed to send: it runs again after
-- 15 minutes times the attempts, and the run exits as failed after
-- 3 attempts.
create or replace function "app_private"."sequence_step_failed"(enrollment_id uuid, step text, error text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "app_private"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "app_private"."sequence_enrollments" x where x."enrollment_id" = sequence_step_failed.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_failed.step then
    return "app_private"."sequence_member_json"(v_member."enrollment_id");
  end if;
  update "app_private"."sequence_enrollments" x
  set "last_error" = left(coalesce(sequence_step_failed.error, 'send failed'), 2000),
    "next_run_at" = now() + make_interval(mins => 15 * greatest(x."attempts", 1)),
    "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id"
  returning * into v_member;
  if v_member."attempts" >= 3 then
    perform "app_private"."sequence_exit"(v_member."enrollment_id", 'failed');
  end if;
  return "app_private"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "app_private"."sequence_step_failed"(uuid, text, text) from public, anon, authenticated;
grant execute on function "app_private"."sequence_step_failed"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block-data sequences
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sequences', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block sequences@1 managed
-- Multi-step outreach sequences whose steps send email through mail-sync, create work items or wait. Each sequence runs as an enrollment program, and a reply on the thread or from the recipient's address ends their run.
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
-- Outreach sequences: steps that send email, create a task or wait. Each
-- sequence runs as the enrollment program sequence:<id>, whose steps are the
-- sequence's steps; a reply ends a recipient's run.
create table if not exists "better_supabase"."sequences" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9-]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "description" text check ("description" is null or length("description") <= 2000),
  "status" text not null default 'draft' check ("status" in ('draft', 'active', 'paused', 'archived')),
  -- An inbound message on the thread, or from the recipient's address, ends
  -- the recipient's run.
  "exit_on_reply" boolean not null default true,
  -- The mailbox email steps send from when the enrollment names none.
  "mail_account_id" uuid,
  -- The steps in order: [{ id, kind: email | task | wait, ... }]. Each is a
  -- step of the enrollment program sequence:<id>.
  "steps" jsonb not null default '[]' check (jsonb_typeof("steps") = 'array'),
  "version" integer not null default 1 check ("version" >= 1),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  constraint "sequences_key_key" unique ("tenant_id", "key")
);
create index if not exists "sequences_account_idx" on "better_supabase"."sequences" ("mail_account_id") where "mail_account_id" is not null;

-- Where a recipient is in a sequence. The enrollment holds the completed
-- steps; this holds the next step, when it runs and who it goes to.
create table if not exists "better_supabase"."sequence_enrollments" (
  "enrollment_id" uuid primary key references "better_supabase"."enrollments" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "sequence_id" uuid not null references "better_supabase"."sequences" ("id") on delete cascade,
  "subject_type" text not null check ("subject_type" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "subject_id" text not null check (length("subject_id") between 1 and 200),
  "address" text check ("address" is null or (length("address") <= 320 and "address" ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  "name" text check ("name" is null or length("name") <= 200),
  "mail_account_id" uuid,
  -- The thread the first email started; later emails reply on it.
  "mail_thread_id" uuid,
  -- The step that runs next, null once every step is done.
  "step" text,
  "next_run_at" timestamptz,
  "status" text not null default 'active' check ("status" in ('active', 'paused', 'completed', 'exited')),
  "exit_reason" text check ("exit_reason" is null or "exit_reason" in ('replied', 'manual', 'failed', 'archived')),
  "attempts" integer not null default 0 check ("attempts" >= 0),
  "last_error" text check ("last_error" is null or length("last_error") <= 2000),
  -- Values for the {{key}} placeholders of the email steps.
  "variables" jsonb not null default '{}' check (jsonb_typeof("variables") = 'object'),
  "enrolled_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (("status" = 'exited') = ("exit_reason" is not null))
);
create index if not exists "sequence_enrollments_parent_idx" on "better_supabase"."sequence_enrollments" ("sequence_id", "status");
create index if not exists "sequence_enrollments_due_idx" on "better_supabase"."sequence_enrollments" ("next_run_at") where "status" = 'active';
create index if not exists "sequence_enrollments_subject_idx" on "better_supabase"."sequence_enrollments" ("tenant_id", "subject_type", "subject_id");
create index if not exists "sequence_enrollments_address_idx" on "better_supabase"."sequence_enrollments" ("tenant_id", lower("address")) where "status" in ('active', 'paused');
create index if not exists "sequence_enrollments_account_idx" on "better_supabase"."sequence_enrollments" ("mail_account_id") where "mail_account_id" is not null;
create index if not exists "sequence_enrollments_thread_idx" on "better_supabase"."sequence_enrollments" ("mail_thread_id") where "mail_thread_id" is not null;

alter table "better_supabase"."sequences" enable row level security;
revoke all on "better_supabase"."sequences" from anon, authenticated;
grant select on "better_supabase"."sequences" to authenticated;
grant all on "better_supabase"."sequences" to service_role;
drop policy if exists "sequences_read" on "better_supabase"."sequences";
create policy "sequences_read" on "better_supabase"."sequences" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));
alter table "better_supabase"."sequence_enrollments" enable row level security;
revoke all on "better_supabase"."sequence_enrollments" from anon, authenticated;
grant select on "better_supabase"."sequence_enrollments" to authenticated;
grant all on "better_supabase"."sequence_enrollments" to service_role;
drop policy if exists "sequence_enrollments_read" on "better_supabase"."sequence_enrollments";
create policy "sequence_enrollments_read" on "better_supabase"."sequence_enrollments" for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')));

-- Checks a steps array: [{ id, kind, ... }] where an email step has a
-- subject and text or html, a task step a title, and a wait step minutes.
create or replace function "better_supabase"."sequence_steps_check"(steps jsonb, mail boolean)
returns void
language plpgsql
immutable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_step jsonb;
  v_ids text[] := '{}';
  v_id text;
begin
  if sequence_steps_check.steps is null or jsonb_typeof(sequence_steps_check.steps) <> 'array' then
    raise exception 'steps must be an array' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_array_length(sequence_steps_check.steps) > 50 then
    raise exception 'a sequence has at most 50 steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  for v_step in select t.value from jsonb_array_elements(sequence_steps_check.steps) t loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'each step must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_id := v_step ->> 'id';
    if v_id is null or v_id !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
      raise exception 'step id: use lowercase letters, digits, "_" or "-"' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    if v_id = any(v_ids) then
      raise exception 'step ids must be unique' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    v_ids := v_ids || v_id;
    case v_step ->> 'kind'
      when 'wait' then
        if jsonb_typeof(v_step -> 'minutes') is distinct from 'number'
          or (v_step ->> 'minutes')::numeric <> trunc((v_step ->> 'minutes')::numeric)
          or (v_step ->> 'minutes')::numeric not between 1 and 525600 then
          raise exception 'a wait step waits 1 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'email' then
        if not sequence_steps_check.mail then
          raise exception 'email steps need the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(trim(v_step ->> 'subject'), '')) not between 1 and 300 then
          raise exception 'an email step needs a subject of 1 to 300 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if coalesce(v_step ->> 'text', v_step ->> 'html') is null then
          raise exception 'an email step needs text or html' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'text', '')) + length(coalesce(v_step ->> 'html', '')) > 200000 then
          raise exception 'an email step''s body is at most 200000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'track' and jsonb_typeof(v_step -> 'track') <> 'boolean' then
          raise exception 'track must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'templateVersionId' and coalesce(v_step ->> 'templateVersionId', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          raise exception 'templateVersionId must be a uuid' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      when 'task' then
        if length(coalesce(trim(v_step ->> 'title'), '')) not between 1 and 200 then
          raise exception 'a task step needs a title of 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if length(coalesce(v_step ->> 'body', '')) > 10000 then
          raise exception 'a task step''s body is at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
        if v_step ? 'dueInMinutes' and (jsonb_typeof(v_step -> 'dueInMinutes') is distinct from 'number'
          or (v_step ->> 'dueInMinutes')::numeric <> trunc((v_step ->> 'dueInMinutes')::numeric)
          or (v_step ->> 'dueInMinutes')::numeric not between 0 and 525600) then
          raise exception 'dueInMinutes must be 0 to 525600 whole minutes' using errcode = '22023', hint = 'SEQUENCE_INVALID';
        end if;
      else
        raise exception 'a step''s kind must be email, task or wait' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end case;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."sequence_steps_check"(jsonb, boolean) from public, anon, authenticated;

-- A recipient in a sequence with their completed steps.
create or replace function "better_supabase"."sequence_member_json"(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."enrollment_id", 'organizationId', x."tenant_id", 'sequenceId', x."sequence_id",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."address", 'name', x."name",
    'accountId', x."mail_account_id", 'threadId', x."mail_thread_id", 'step', x."step", 'nextRunAt', x."next_run_at",
    'status', x."status", 'exitReason', x."exit_reason", 'attempts', x."attempts", 'lastError', x."last_error",
    'variables', x."variables", 'enrolledBy', x."enrolled_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at",
    'completedSteps', coalesce((select jsonb_agg(y."step" order by y."completed_at", y."step") from "better_supabase"."enrollment_steps" y where y."enrollment_id" = x."enrollment_id"), '[]'::jsonb))
  from "better_supabase"."sequence_enrollments" x
  where x."enrollment_id" = sequence_member_json.enrollment_id;
$$;
revoke execute on function "better_supabase"."sequence_member_json"(uuid) from public, anon, authenticated;

-- Moves a recipient to their first step not done: a wait step runs once its
-- minutes pass, the others right away. With every step done the run
-- completes. A recipient already on that step keeps their schedule.
create or replace function "better_supabase"."sequence_place"(enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
  v_steps jsonb;
  v_next jsonb;
begin
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_place.enrollment_id for update;
  if v_member."enrollment_id" is null or v_member."status" in ('completed', 'exited') then
    return;
  end if;
  select y."steps" into v_steps from "better_supabase"."sequences" y where y."id" = v_member."sequence_id";
  select t.value into v_next
  from jsonb_array_elements(coalesce(v_steps, '[]'::jsonb)) with ordinality as t(value, ord)
  where not exists (select 1 from "better_supabase"."enrollment_steps" z where z."enrollment_id" = v_member."enrollment_id" and z."step" = t.value ->> 'id')
  order by t.ord
  limit 1;
  if v_next is null then
    update "better_supabase"."sequence_enrollments" x
    set "status" = 'completed', "step" = null, "next_run_at" = null, "attempts" = 0, "last_error" = null, "updated_at" = now()
    where x."enrollment_id" = v_member."enrollment_id"
    returning * into v_member;
    null;
    return;
  end if;
  if (v_next ->> 'id') is not distinct from v_member."step" then
    return;
  end if;
  update "better_supabase"."sequence_enrollments" x
  set "step" = v_next ->> 'id',
    "next_run_at" = case when v_next ->> 'kind' = 'wait' then now() + make_interval(mins => (v_next ->> 'minutes')::integer) else now() end,
    "attempts" = 0, "last_error" = null, "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id";
end;
$$;
revoke execute on function "better_supabase"."sequence_place"(uuid) from public, anon, authenticated;

-- Ends a recipient's run (reason: replied, manual, failed or archived) and
-- cancels their enrollment; the completed steps stay.
create or replace function "better_supabase"."sequence_exit"(enrollment_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  update "better_supabase"."sequence_enrollments" x
  set "status" = 'exited', "exit_reason" = sequence_exit.reason, "next_run_at" = null, "updated_at" = now()
  where x."enrollment_id" = sequence_exit.enrollment_id and x."status" in ('active', 'paused')
  returning * into v_member;
  if v_member."enrollment_id" is null then
    return;
  end if;
  update "better_supabase"."enrollments" x
  set "status" = 'cancelled', "cancelled_at" = now(), "updated_at" = now()
  where x."id" = v_member."enrollment_id" and x."status" <> 'cancelled';
  if sequence_exit.reason = 'manual' then
    null;
  else
    null;
  end if;
end;
$$;
revoke execute on function "better_supabase"."sequence_exit"(uuid, text) from public, anon, authenticated;

-- Marks the recipient's current step done and moves them on.
create or replace function "better_supabase"."sequence_step_done"(enrollment_id uuid, step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  perform "better_supabase"."enrollment_mark"(sequence_step_done.enrollment_id, sequence_step_done.step, true, null);
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_done.enrollment_id;
  null;
  perform "better_supabase"."sequence_place"(sequence_step_done.enrollment_id);
end;
$$;
revoke execute on function "better_supabase"."sequence_step_done"(uuid, text) from public, anon, authenticated;

-- Gives every running recipient of a sequence its current steps and moves
-- them to their first step not done.
create or replace function "better_supabase"."sequence_resync"(sequence_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "better_supabase"."sequences";
  v_member "better_supabase"."sequence_enrollments";
begin
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = sequence_resync.sequence_id;
  for v_member in
    select * from "better_supabase"."sequence_enrollments" x
    where x."sequence_id" = sequence_resync.sequence_id and x."status" in ('active', 'paused')
    for update
  loop
    perform "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
      v_member."subject_type", v_member."subject_id", null);
    perform "better_supabase"."sequence_place"(v_member."enrollment_id");
  end loop;
end;
$$;
revoke execute on function "better_supabase"."sequence_resync"(uuid) from public, anon, authenticated;

-- Creates or changes a sequence. sequence is { id?, key, name,
-- description, status, exitOnReply, accountId, steps }; keys left out keep
-- their value. Changing the steps raises the version and moves running
-- recipients onto the new steps. Archiving ends every run.
create or replace function "better_supabase"."save_sequence"(tenant uuid, sequence jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."sequences";
  v_row "better_supabase"."sequences";
  v_key text;
  v_name text;
  v_description text;
  v_status text;
  v_exit boolean;
  v_account uuid;
  v_steps jsonb;
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_sequence.tenant is not null and coalesce(better_supabase.can('tenant', save_sequence.tenant, 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if save_sequence.sequence is null or jsonb_typeof(save_sequence.sequence) <> 'object' then
    raise exception 'sequence must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_id := nullif(save_sequence.sequence ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."sequences" x
    where x."id" = v_id and x."tenant_id" = save_sequence.tenant
    for update;
    if v_old."id" is null then
      raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_sequence.sequence ->> 'key', v_old."key");
  v_name := trim(coalesce(save_sequence.sequence ->> 'name', v_old."name"));
  v_description := case when save_sequence.sequence ? 'description'
    then nullif(trim(save_sequence.sequence ->> 'description'), '') else v_old."description" end;
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old."status", 'draft');
  v_exit := case when save_sequence.sequence ? 'exitOnReply'
    then (save_sequence.sequence ->> 'exitOnReply')::boolean else coalesce(v_old."exit_on_reply", true) end;
  v_account := case when save_sequence.sequence ? 'accountId'
    then nullif(save_sequence.sequence ->> 'accountId', '')::uuid else v_old."mail_account_id" end;
  v_steps := case when save_sequence.sequence ? 'steps'
    then save_sequence.sequence -> 'steps' else coalesce(v_old."steps", '[]'::jsonb) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is not null and v_key <> v_old."key" then
    raise exception 'a sequence''s key can''t change' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    raise exception 'name must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_description) > 2000 then
    raise exception 'description must be at most 2000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_status not in ('draft', 'active', 'paused', 'archived') then
    raise exception 'status must be draft, active, paused or archived' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_exit is null then
    raise exception 'exitOnReply must be true or false' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  perform "better_supabase"."sequence_steps_check"(v_steps, false);
  if v_status = 'active' and jsonb_array_length(v_steps) = 0 then
    raise exception 'an active sequence needs at least one step' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null then
    raise exception 'accountId needs the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."sequences" ("tenant_id", "key", "name", "description", "status", "exit_on_reply", "mail_account_id", "steps", "created_by")
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, auth.uid())
    returning * into v_row;
  else
    update "better_supabase"."sequences" x
    set "name" = v_name, "description" = v_description, "status" = v_status, "exit_on_reply" = v_exit,
      "mail_account_id" = v_account, "steps" = v_steps,
      "version" = x."version" + case when x."steps" is distinct from v_steps then 1 else 0 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
    if v_old."steps" is distinct from v_row."steps" then
      perform "better_supabase"."sequence_resync"(v_row."id");
    end if;
    if v_row."status" = 'archived' and v_old."status" <> 'archived' then
      for v_member in
        select * from "better_supabase"."sequence_enrollments" x
        where x."sequence_id" = v_row."id" and x."status" in ('active', 'paused')
      loop
        perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'archived');
      end loop;
    end if;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."save_sequence"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_sequence"(uuid, jsonb) to authenticated, service_role;

-- An organization's sequences with their recipient counts, by name. status
-- filters; without it archived sequences stay out.
create or replace function "better_supabase"."list_sequences"(tenant uuid, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequences.tenant is not null and coalesce(better_supabase.can('tenant', list_sequences.tenant, 'sequences.read'), false))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = x."id")) order by x."name", x."id")
    from "better_supabase"."sequences" x
    where x."tenant_id" = list_sequences.tenant
      and (case when list_sequences.status is null then x."status" <> 'archived' else x."status" = list_sequences.status end)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_sequences"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_sequences"(uuid, text) to authenticated, service_role;

-- One sequence with its recipient counts.
create or replace function "better_supabase"."get_sequence"(sequence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."sequences";
begin
  select * into v_row from "better_supabase"."sequences" x where x."id" = get_sequence.sequence_id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.read'), false))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where m."status" = 'active'), 'paused', count(*) filter (where m."status" = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'exited'),
      'replied', count(*) filter (where m."exit_reason" = 'replied'))
    from "better_supabase"."sequence_enrollments" m where m."sequence_id" = v_row."id"));
end;
$$;
revoke execute on function "better_supabase"."get_sequence"(uuid) from public, anon;
grant execute on function "better_supabase"."get_sequence"(uuid) to authenticated, service_role;

-- Deletes a sequence with its enrollments; false when there was none.
create or replace function "better_supabase"."delete_sequence"(sequence_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."sequences";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."sequences" x where x."id" = delete_sequence.sequence_id for update;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.manage'), false))) then
    raise exception 'not allowed to manage sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  delete from "better_supabase"."enrollments" x where x."tenant_id" = v_row."tenant_id" and x."program" = ('sequence:' || v_row."id"::text);
  delete from "better_supabase"."sequences" x where x."id" = v_row."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_sequence"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_sequence"(uuid) to authenticated, service_role;

-- Enrolls a record (subject_type, subject_id) in an active sequence. attrs
-- is { address, name, accountId, variables }: a person's email and name fill
-- address and name when left out, and the mailbox defaults to the
-- sequence's, then the caller's. A finished or exited run starts over.
create or replace function "better_supabase"."enroll_in_sequence"(sequence_id uuid, subject_type text, subject_id text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence "better_supabase"."sequences";
  v_row "better_supabase"."enrollments";
  v_member "better_supabase"."sequence_enrollments";
  v_attrs jsonb := coalesce(enroll_in_sequence.attrs, '{}'::jsonb);
  v_address text;
  v_name text;
  v_email text;
  v_label text;
  v_account uuid;
  v_owner uuid;
  v_variables jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = enroll_in_sequence.sequence_id;
  if v_sequence."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence not found' using errcode = 'P0002', hint = 'SEQUENCE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_sequence."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_sequence."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to enroll in sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if v_sequence."status" <> 'active' then
    raise exception 'only an active sequence takes enrollments' using errcode = '55000', hint = 'SEQUENCE_NOT_ACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_type is null or enroll_in_sequence.subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'subject_type: use lowercase letters, digits or _' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if enroll_in_sequence.subject_id is null or length(enroll_in_sequence.subject_id) not between 1 and 200 then
    raise exception 'subject_id must be 1 to 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  v_address := nullif(trim(v_attrs ->> 'address'), '');
  v_name := nullif(trim(v_attrs ->> 'name'), '');
  v_account := nullif(v_attrs ->> 'accountId', '')::uuid;
  v_variables := coalesce(v_attrs -> 'variables', '{}'::jsonb);
  
  if v_address is not null and (length(v_address) > 320 or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$') then
    raise exception 'address must be an email address' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if length(v_name) > 200 then
    raise exception 'name must be at most 200 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if jsonb_typeof(v_variables) <> 'object' or length(v_variables::text) > 10000 then
    raise exception 'variables must be an object of at most 10000 characters' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_address is null and exists (select 1 from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'kind' = 'email') then
    raise exception 'the recipient needs an email address for the sequence''s email steps' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_account is not null then
    raise exception 'accountId needs the mail-sync block' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_sequence."tenant_id" and x."program" = ('sequence:' || v_sequence."id"::text)
    and x."subject_type" = enroll_in_sequence.subject_type and x."subject_id" = enroll_in_sequence.subject_id
  for update;
  if v_row."id" is not null then
    select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_row."id" for update;
    if v_member."status" in ('active', 'paused') then
      return "better_supabase"."sequence_member_json"(v_row."id");
    end if;
    -- Starting over: clearing the steps makes enrollment_ensure take the
    -- current ones, with none done.
    delete from "better_supabase"."enrollment_steps" x where x."enrollment_id" = v_row."id";
    update "better_supabase"."enrollments" x
    set "status" = 'active', "cancelled_at" = null, "completed_at" = null, "enrolled_by" = auth.uid(),
      "enrolled_at" = now(), "steps" = '{}'
    where x."id" = v_row."id";
  end if;
  v_id := "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
    enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  insert into "better_supabase"."sequence_enrollments" ("enrollment_id", "tenant_id", "sequence_id", "subject_type", "subject_id", "address", "name",
    "mail_account_id", "variables", "enrolled_by")
  values (v_id, v_sequence."tenant_id", v_sequence."id", enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, v_address, v_name,
    v_account, v_variables, auth.uid())
  on conflict ("enrollment_id") do update
  set "address" = excluded."address", "name" = excluded."name", "mail_account_id" = excluded."mail_account_id",
    "variables" = excluded."variables", "enrolled_by" = excluded."enrolled_by", "status" = 'active',
    "exit_reason" = null, "step" = null, "next_run_at" = null, "mail_thread_id" = null, "attempts" = 0,
    "last_error" = null, "updated_at" = now();
  perform "better_supabase"."sequence_place"(v_id);
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_id;
  null;
  return "better_supabase"."sequence_member_json"(v_id);
end;
$$;
revoke execute on function "better_supabase"."enroll_in_sequence"(uuid, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."enroll_in_sequence"(uuid, text, text, jsonb) to authenticated, service_role;

-- Pauses, resumes or exits a recipient's run (action: pause, resume, exit).
create or replace function "better_supabase"."change_sequence_enrollment"(enrollment_id uuid, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = change_sequence_enrollment.enrollment_id for update;
  if v_member."enrollment_id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_member."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_member."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to change sequence enrollments' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  case change_sequence_enrollment.action
    when 'pause' then
      if v_member."status" <> 'active' then
        raise exception 'only an active run can be paused' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "better_supabase"."sequence_enrollments" x set "status" = 'paused', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      null;
    when 'resume' then
      if v_member."status" <> 'paused' then
        raise exception 'only a paused run can be resumed' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      update "better_supabase"."sequence_enrollments" x set "status" = 'active', "updated_at" = now()
      where x."enrollment_id" = v_member."enrollment_id"
      returning * into v_member;
      null;
    when 'exit' then
      if v_member."status" not in ('active', 'paused') then
        raise exception 'only an active or paused run can be exited' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'manual');
    else
      raise exception 'action must be pause, resume or exit' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end case;
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) from public, anon;
grant execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) to authenticated, service_role;

-- An organization's sequence recipients, newest first. filter is
-- { sequence, subjectType, subjectId, status, limit, before }: before is a
-- createdAt from the previous page.
create or replace function "better_supabase"."list_sequence_enrollments"(tenant uuid, filter jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filter jsonb := coalesce(list_sequence_enrollments.filter, '{}'::jsonb);
  v_parent uuid := nullif(v_filter ->> 'sequence', '')::uuid;
begin
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', list_sequence_enrollments.tenant, 'sequences.enroll'), false)))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filter) <> 'object' then
    raise exception 'filter must be an object' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg("better_supabase"."sequence_member_json"(y."enrollment_id") order by y."created_at" desc, y."enrollment_id" desc)
    from (
      select x."enrollment_id", x."created_at"
      from "better_supabase"."sequence_enrollments" x
      where x."tenant_id" = list_sequence_enrollments.tenant
        and (v_parent is null or x."sequence_id" = v_parent)
        and (v_filter ->> 'subjectType' is null or x."subject_type" = v_filter ->> 'subjectType')
        and (v_filter ->> 'subjectId' is null or x."subject_id" = v_filter ->> 'subjectId')
        and (v_filter ->> 'status' is null or x."status" = v_filter ->> 'status')
        and (v_filter ->> 'before' is null or x."created_at" < (v_filter ->> 'before')::timestamptz)
      order by x."created_at" desc, x."enrollment_id" desc
      limit least(greatest(coalesce((v_filter ->> 'limit')::integer, 50), 1), 200)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_sequence_enrollments"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_sequence_enrollments"(uuid, jsonb) to authenticated, service_role;

-- Runs the steps that are due, oldest first: wait steps finish, task steps
-- create a work item for whoever enrolled the recipient, and email steps
-- are claimed for 10 minutes and returned for the caller to send. Call
-- sequence_step_sent or sequence_step_failed with each result. Returns
-- { ran, emails: [{ enrollmentId, sequenceId, organizationId, accountId,
-- threadId, to, step, variables, attempt, subjectType, subjectId }] }.
create or replace function "better_supabase"."run_due_sequences"(max_count integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_due "better_supabase"."sequence_enrollments";
  v_member "better_supabase"."sequence_enrollments";
  v_sequence "better_supabase"."sequences";
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  for v_due in
    select x.* from "better_supabase"."sequence_enrollments" x
    join "better_supabase"."sequences" y on y."id" = x."sequence_id"
    where x."status" = 'active' and x."next_run_at" <= now() and y."status" = 'active'
    order by x."next_run_at", x."enrollment_id"
    limit least(greatest(coalesce(run_due_sequences.max_count, 50), 1), 500)
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = v_due."enrollment_id";
      exit when v_member."status" <> 'active' or v_member."step" is null or v_member."next_run_at" > now();
      select * into v_sequence from "better_supabase"."sequences" x where x."id" = v_member."sequence_id";
      v_step := (select t.value from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'id' = v_member."step");
      if v_step is null then
        perform "better_supabase"."sequence_place"(v_member."enrollment_id");
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        update "better_supabase"."sequence_enrollments" x
        set "attempts" = x."attempts" + 1, "next_run_at" = now() + interval '10 minutes', "updated_at" = now()
        where x."enrollment_id" = v_member."enrollment_id"
        returning * into v_member;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_member."enrollment_id", 'sequenceId', v_member."sequence_id", 'organizationId', v_member."tenant_id",
          'accountId', coalesce(v_member."mail_account_id", v_sequence."mail_account_id"), 'threadId', v_member."mail_thread_id",
          'to', jsonb_build_object('address', v_member."address", 'name', v_member."name"),
          'step', v_step, 'variables', v_member."variables", 'attempt', v_member."attempts",
          'subjectType', v_member."subject_type", 'subjectId', v_member."subject_id"));
        exit;
      end if;
      perform "better_supabase"."sequence_step_done"(v_member."enrollment_id", v_member."step");
      v_ran := v_ran + 1;
    end loop;
  end loop;
  return jsonb_build_object('ran', v_ran, 'emails', v_emails);
end;
$$;
revoke execute on function "better_supabase"."run_due_sequences"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."run_due_sequences"(integer) to service_role;

-- Records that a claimed email step went out as message_id (a mail-sync
-- message, or null): later emails reply on its thread. A stale result, for
-- a run that moved on, changes nothing.
create or replace function "better_supabase"."sequence_step_sent"(enrollment_id uuid, step text, message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_sent.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_sent.step then
    return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
  end if;
  perform "better_supabase"."sequence_step_done"(v_member."enrollment_id", sequence_step_sent.step);
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."sequence_step_sent"(uuid, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."sequence_step_sent"(uuid, text, uuid) to service_role;

-- Records that a claimed email step failed to send: it runs again after
-- 15 minutes times the attempts, and the run exits as failed after
-- 3 attempts.
create or replace function "better_supabase"."sequence_step_failed"(enrollment_id uuid, step text, error text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member "better_supabase"."sequence_enrollments";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_member from "better_supabase"."sequence_enrollments" x where x."enrollment_id" = sequence_step_failed.enrollment_id for update;
  if v_member."enrollment_id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if v_member."status" <> 'active' or v_member."step" is distinct from sequence_step_failed.step then
    return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
  end if;
  update "better_supabase"."sequence_enrollments" x
  set "last_error" = left(coalesce(sequence_step_failed.error, 'send failed'), 2000),
    "next_run_at" = now() + make_interval(mins => 15 * greatest(x."attempts", 1)),
    "updated_at" = now()
  where x."enrollment_id" = v_member."enrollment_id"
  returning * into v_member;
  if v_member."attempts" >= 3 then
    perform "better_supabase"."sequence_exit"(v_member."enrollment_id", 'failed');
  end if;
  return "better_supabase"."sequence_member_json"(v_member."enrollment_id");
end;
$$;
revoke execute on function "better_supabase"."sequence_step_failed"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."sequence_step_failed"(uuid, text, text) to service_role;

-- blocks.sequences.api: entry points for the Data API.
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

create or replace function "api"."save_sequence"(tenant uuid, sequence jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_sequence"($1, $2) $$;
revoke execute on function "api"."save_sequence"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_sequence"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_sequences"(tenant uuid, status text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_sequences"($1, $2) $$;
revoke execute on function "api"."list_sequences"(uuid, text) from public, anon;
grant execute on function "api"."list_sequences"(uuid, text) to authenticated, service_role;

create or replace function "api"."get_sequence"(sequence_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_sequence"($1) $$;
revoke execute on function "api"."get_sequence"(uuid) from public, anon;
grant execute on function "api"."get_sequence"(uuid) to authenticated, service_role;

create or replace function "api"."delete_sequence"(sequence_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_sequence"($1) $$;
revoke execute on function "api"."delete_sequence"(uuid) from public, anon;
grant execute on function "api"."delete_sequence"(uuid) to authenticated, service_role;

create or replace function "api"."enroll_in_sequence"(sequence_id uuid, subject_type text, subject_id text, attrs jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enroll_in_sequence"($1, $2, $3, $4) $$;
revoke execute on function "api"."enroll_in_sequence"(uuid, text, text, jsonb) from public, anon;
grant execute on function "api"."enroll_in_sequence"(uuid, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."change_sequence_enrollment"(enrollment_id uuid, action text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."change_sequence_enrollment"($1, $2) $$;
revoke execute on function "api"."change_sequence_enrollment"(uuid, text) from public, anon;
grant execute on function "api"."change_sequence_enrollment"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_sequence_enrollments"(tenant uuid, filter jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_sequence_enrollments"($1, $2) $$;
revoke execute on function "api"."list_sequence_enrollments"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_sequence_enrollments"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."run_due_sequences"(max_count integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."run_due_sequences"($1) $$;
revoke execute on function "api"."run_due_sequences"(integer) from public, anon, authenticated;
grant execute on function "api"."run_due_sequences"(integer) to service_role;

create or replace function "api"."sequence_step_sent"(enrollment_id uuid, step text, message_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sequence_step_sent"($1, $2, $3) $$;
revoke execute on function "api"."sequence_step_sent"(uuid, text, uuid) from public, anon, authenticated;
grant execute on function "api"."sequence_step_sent"(uuid, text, uuid) to service_role;

create or replace function "api"."sequence_step_failed"(enrollment_id uuid, step text, error text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sequence_step_failed"($1, $2, $3) $$;
revoke execute on function "api"."sequence_step_failed"(uuid, text, text) from public, anon, authenticated;
grant execute on function "api"."sequence_step_failed"(uuid, text, text) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_138_sequences.sql
-- better-supabase module: sequences
-- @bsb-block-data sequences
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('sequences', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
