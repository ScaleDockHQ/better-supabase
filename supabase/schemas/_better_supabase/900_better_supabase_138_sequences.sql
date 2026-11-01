-- better-supabase module: sequences
-- @bsb-block sequences@2 managed
-- @bsb-hash sha256:a66bdab824a0d702a9465cc155c0d8253626383e0df59d180265244dc8687ce9
-- Multi-step outreach sequences whose steps send email through mail-sync, create work items or wait. Each sequence runs as an enrollment program, and a reply on the thread or from the recipient's address ends their run.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."sequences";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."sequences";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."sequences";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."sequences";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."sequences";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

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

-- A recipient's run is their enrollment in the program sequence:<id>: these
-- columns say who it goes to and how sending went, and the open step row is
-- the step that runs next, due when it runs.
alter table "better_supabase"."enrollments" add column if not exists "sequence_id" uuid references "better_supabase"."sequences" ("id") on delete cascade;
alter table "better_supabase"."enrollments" add column if not exists "sequence_address" text check ("sequence_address" is null or (length("sequence_address") <= 320 and "sequence_address" ~ '^[^@[:space:]]+@[^@[:space:]]+$'));
alter table "better_supabase"."enrollments" add column if not exists "sequence_name" text check ("sequence_name" is null or length("sequence_name") <= 200);
alter table "better_supabase"."enrollments" add column if not exists "sequence_mail_account_id" uuid references "better_supabase"."mail_accounts" ("id") on delete set null;
alter table "better_supabase"."enrollments" add column if not exists "sequence_mail_thread_id" uuid references "better_supabase"."mail_threads" ("id") on delete set null;
alter table "better_supabase"."enrollments" add column if not exists "sequence_attempts" integer not null default 0 check ("sequence_attempts" >= 0);
alter table "better_supabase"."enrollments" add column if not exists "sequence_last_error" text check ("sequence_last_error" is null or length("sequence_last_error") <= 2000);
alter table "better_supabase"."enrollments" add column if not exists "sequence_variables" jsonb not null default '{}' check (jsonb_typeof("sequence_variables") = 'object');
create index if not exists "enrollments_sequence_idx" on "better_supabase"."enrollments" ("sequence_id", "status") where "sequence_id" is not null;
create index if not exists "enrollments_sequence_address_idx" on "better_supabase"."enrollments" ("tenant_id", lower("sequence_address")) where "sequence_id" is not null and "status" = 'active';
create index if not exists "enrollments_sequence_account_idx" on "better_supabase"."enrollments" ("sequence_mail_account_id") where "sequence_mail_account_id" is not null;
create index if not exists "enrollments_sequence_thread_idx" on "better_supabase"."enrollments" ("sequence_mail_thread_id") where "sequence_mail_thread_id" is not null;
create index if not exists "enrollment_steps_open_due_idx" on "better_supabase"."enrollment_steps" ("due_at") where "completed_at" is null;

alter table "better_supabase"."sequences" enable row level security;
revoke all on "better_supabase"."sequences" from public, anon, authenticated;
grant select on "better_supabase"."sequences" to authenticated;
grant all on "better_supabase"."sequences" to service_role;
drop policy if exists "sequences_read" on "better_supabase"."sequences";
create policy sequences_read on "better_supabase"."sequences"
  for select to authenticated
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
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'sequenceId', x."sequence_id",
    'subjectType', x."subject_type", 'subjectId', x."subject_id", 'address', x."sequence_address", 'name', x."sequence_name",
    'accountId', x."sequence_mail_account_id", 'threadId', x."sequence_mail_thread_id", 'step', o."step", 'nextRunAt', o."due_at",
    'status', (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end), 'exitReason', case when x."status" = 'cancelled' then x."cancel_reason" end,
    'attempts', x."sequence_attempts", 'lastError', x."sequence_last_error",
    'variables', x."sequence_variables", 'enrolledBy', x."enrolled_by", 'createdAt', x."enrolled_at", 'updatedAt', x."updated_at",
    'completedSteps', coalesce((select jsonb_agg(y."step" order by y."completed_at", y."step") from "better_supabase"."enrollment_steps" y
      where y."enrollment_id" = x."id" and y."completed_at" is not null), '[]'::jsonb))
  from "better_supabase"."enrollments" x
  left join "better_supabase"."enrollment_steps" o on o."enrollment_id" = x."id" and o."completed_at" is null
  where x."id" = sequence_member_json.enrollment_id and x."sequence_id" is not null;
$$;
revoke execute on function "better_supabase"."sequence_member_json"(uuid) from public, anon, authenticated;

-- Moves a recipient to their first step not done: its open step row is due
-- once a wait step's minutes pass, the others right away. A recipient already
-- on that step keeps their schedule. A run that ended, or has every step
-- done, keeps no open step.
create or replace function "better_supabase"."sequence_place"(enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments";
  v_steps jsonb;
  v_next jsonb;
  v_current text;
  v_due timestamptz;
begin
  select * into v_row from "better_supabase"."enrollments" x
  where x."id" = sequence_place.enrollment_id and x."sequence_id" is not null
  for update;
  if v_row."id" is null then
    return;
  end if;
  if v_row."status" <> 'active' then
    delete from "better_supabase"."enrollment_steps" y where y."enrollment_id" = v_row."id" and y."completed_at" is null;
    return;
  end if;
  select y."steps" into v_steps from "better_supabase"."sequences" y where y."id" = v_row."sequence_id";
  select t.value into v_next
  from jsonb_array_elements(coalesce(v_steps, '[]'::jsonb)) with ordinality as t(value, ord)
  where not exists (
    select 1 from "better_supabase"."enrollment_steps" z
    where z."enrollment_id" = v_row."id" and z."step" = t.value ->> 'id' and z."completed_at" is not null
  )
  order by t.ord
  limit 1;
  select o."step", o."due_at" into v_current, v_due from "better_supabase"."enrollment_steps" o where o."enrollment_id" = v_row."id" and o."completed_at" is null limit 1;
  if v_next is not null and (v_next ->> 'id') is not distinct from v_current then
    return;
  end if;
  delete from "better_supabase"."enrollment_steps" y where y."enrollment_id" = v_row."id" and y."completed_at" is null;
  if v_next is not null then
    insert into "better_supabase"."enrollment_steps" ("enrollment_id", "tenant_id", "step", "due_at", "completed_by", "completed_at")
    values (v_row."id", v_row."tenant_id", v_next ->> 'id',
      case when v_next ->> 'kind' = 'wait' then now() + make_interval(mins => (v_next ->> 'minutes')::integer) else now() end, null, null);
  end if;
  update "better_supabase"."enrollments" x
  set "sequence_attempts" = 0, "sequence_last_error" = null, "updated_at" = now()
  where x."id" = v_row."id";
end;
$$;
revoke execute on function "better_supabase"."sequence_place"(uuid) from public, anon, authenticated;

-- Ends a recipient's run (reason: replied, manual, failed or archived) by
-- cancelling their enrollment; the completed steps stay. A manual exit is
-- audited.
create or replace function "better_supabase"."sequence_exit"(enrollment_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform "better_supabase"."enrollment_cancel"(sequence_exit.enrollment_id, sequence_exit.reason,
    case when sequence_exit.reason = 'manual' then auth.uid() end);
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
begin
  perform "better_supabase"."enrollment_mark"(sequence_step_done.enrollment_id, sequence_step_done.step, true, null);
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
  v_row "better_supabase"."enrollments";
begin
  select * into v_sequence from "better_supabase"."sequences" x where x."id" = sequence_resync.sequence_id;
  for v_row in
    select * from "better_supabase"."enrollments" x
    where x."sequence_id" = sequence_resync.sequence_id and x."status" = 'active'
    for update
  loop
    perform "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
      v_row."subject_type", v_row."subject_id", null);
    perform "better_supabase"."sequence_place"(v_row."id");
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
  v_run uuid;
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
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old."status"::text, 'draft');
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_sequence_save"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using save_sequence.tenant, save_sequence.sequence;
    end if;
  end;
  if v_old."id" is null then
    insert into "better_supabase"."sequences" ("tenant_id", "key", "name", "description", "status", "exit_on_reply", "mail_account_id", "steps", "version", "created_by")
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, 1, auth.uid())
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
      for v_run in
        select x."id" from "better_supabase"."enrollments" x
        where x."sequence_id" = v_row."id" and x."status" = 'active'
      loop
        perform "better_supabase"."sequence_exit"(v_run, 'archived');
      end loop;
    end if;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('sequence.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.created',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'created a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('sequence.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'sequences/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/sequences');
  perform better_supabase.audit_event(
    event_type => 'sequence.updated',
    category => 'data',
    target_type => 'sequence',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'updated a sequence',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_sequence_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = v_row."id"));
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
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'status', x."status", 'exitOnReply', x."exit_on_reply", 'accountId', x."mail_account_id", 'steps', x."steps", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = x."id")) order by x."name", x."id")
    from "better_supabase"."sequences" x
    where x."tenant_id" = list_sequences.tenant
      and (case when list_sequences.status is null then x."status" <> 'archived' else x."status"::text = list_sequences.status end)
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'status', v_row."status", 'exitOnReply', v_row."exit_on_reply", 'accountId', v_row."mail_account_id", 'steps', v_row."steps", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('counts', (select jsonb_build_object('active', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'active'), 'paused', count(*) filter (where (case when m."status" = 'cancelled' then 'exited' when m."status" = 'completed' then 'completed' when m."paused_at" is not null then 'paused' else 'active' end) = 'paused'),
      'completed', count(*) filter (where m."status" = 'completed'), 'exited', count(*) filter (where m."status" = 'cancelled'),
      'replied', count(*) filter (where m."status" = 'cancelled' and m."cancel_reason" = 'replied'))
    from "better_supabase"."enrollments" m where m."sequence_id" = v_row."id"));
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
  if enroll_in_sequence.subject_type is null or enroll_in_sequence.subject_type !~ '^[a-z][a-z0-9_-]{0,62}$' then
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_sequence_enroll"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using enroll_in_sequence.sequence_id, enroll_in_sequence.subject_type, enroll_in_sequence.subject_id;
    end if;
  end;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_sequence."tenant_id" and x."program" = ('sequence:' || v_sequence."id"::text)
    and x."subject_type" = enroll_in_sequence.subject_type and x."subject_id" = enroll_in_sequence.subject_id
  for update;
  if v_row."id" is not null and v_row."status" = 'active' then
    return "better_supabase"."sequence_member_json"(v_row."id");
  end if;
  if v_row."id" is not null then
    -- Starting over: the run begins again with none of the steps done.
    perform "better_supabase"."enrollment_restart"(v_row."id", v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord), auth.uid());
    v_id := v_row."id";
  else
    v_id := "better_supabase"."enrollment_ensure"(v_sequence."tenant_id", ('sequence:' || v_sequence."id"::text), v_sequence."version", array(select t.value ->> 'id' from jsonb_array_elements(v_sequence."steps") with ordinality as t(value, ord) order by t.ord),
      enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  end if;
  update "better_supabase"."enrollments" x
  set "sequence_id" = v_sequence."id", "sequence_address" = v_address, "sequence_name" = v_name, "sequence_mail_account_id" = v_account,
    "sequence_mail_thread_id" = null, "sequence_variables" = v_variables, "sequence_attempts" = 0, "sequence_last_error" = null, "updated_at" = now()
  where x."id" = v_id;
  perform "better_supabase"."sequence_place"(v_id);
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_sequence_enroll"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
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
  v_row "better_supabase"."enrollments";
  v_status text;
begin
  select * into v_row from "better_supabase"."enrollments" x
  where x."id" = change_sequence_enrollment.enrollment_id and x."sequence_id" is not null
  for update;
  if v_row."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.enroll'), false))) then
    raise exception 'not allowed to change sequence enrollments' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  v_status := (case when v_row."status" = 'cancelled' then 'exited' when v_row."status" = 'completed' then 'completed' when v_row."paused_at" is not null then 'paused' else 'active' end);
  case change_sequence_enrollment.action
    when 'pause' then
      if v_status <> 'active' then
        raise exception 'only an active run can be paused' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      perform "better_supabase"."enrollment_pause"(v_row."id", true, auth.uid());
    when 'resume' then
      if v_status <> 'paused' then
        raise exception 'only a paused run can be resumed' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      perform "better_supabase"."enrollment_pause"(v_row."id", false, auth.uid());
    when 'exit' then
      if v_status not in ('active', 'paused') then
        raise exception 'only an active or paused run can be exited' using errcode = '22023', hint = 'SEQUENCE_INVALID';
      end if;
      perform "better_supabase"."sequence_exit"(v_row."id", 'manual');
    else
      raise exception 'action must be pause, resume or exit' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end case;
  return "better_supabase"."sequence_member_json"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) from public, anon;
grant execute on function "better_supabase"."change_sequence_enrollment"(uuid, text) to authenticated, service_role;

-- An organization's sequence recipients, newest first. filter is
-- { sequence, subjectType, subjectId, status, limit, before }: before is a
-- createdAt (when the run started) from the previous page.
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
    select jsonb_agg("better_supabase"."sequence_member_json"(y."id") order by y."enrolled_at" desc, y."id" desc)
    from (
      select x."id", x."enrolled_at"
      from "better_supabase"."enrollments" x
      where x."tenant_id" = list_sequence_enrollments.tenant and x."sequence_id" is not null
        and (v_parent is null or x."sequence_id" = v_parent)
        and (v_filter ->> 'subjectType' is null or x."subject_type" = v_filter ->> 'subjectType')
        and (v_filter ->> 'subjectId' is null or x."subject_id" = v_filter ->> 'subjectId')
        and (v_filter ->> 'status' is null or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = v_filter ->> 'status')
        and (v_filter ->> 'before' is null or x."enrolled_at" < (v_filter ->> 'before')::timestamptz)
      order by x."enrolled_at" desc, x."id" desc
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
  v_due uuid;
  v_row "better_supabase"."enrollments";
  v_sequence "better_supabase"."sequences";
  v_current text;
  v_next_run timestamptz;
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  for v_due in
    select x."id" from "better_supabase"."enrollments" x
    join "better_supabase"."enrollment_steps" o on o."enrollment_id" = x."id" and o."completed_at" is null
    join "better_supabase"."sequences" y on y."id" = x."sequence_id"
    where o."due_at" <= now() and x."status" = 'active' and x."paused_at" is null and y."status" = 'active'
    order by o."due_at", x."id"
    limit least(greatest(coalesce(run_due_sequences.max_count, 50), 1), 500)
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_row from "better_supabase"."enrollments" x where x."id" = v_due;
      v_current := null;
      v_next_run := null;
      select o."step", o."due_at" into v_current, v_next_run from "better_supabase"."enrollment_steps" o where o."enrollment_id" = v_due and o."completed_at" is null limit 1;
      exit when v_row."status" <> 'active' or v_row."paused_at" is not null or v_current is null or v_next_run > now();
      select * into v_sequence from "better_supabase"."sequences" x where x."id" = v_row."sequence_id";
      v_step := (select t.value from jsonb_array_elements(v_sequence."steps") t where t.value ->> 'id' = v_current);
      if v_step is null then
        delete from "better_supabase"."enrollment_steps" y where y."enrollment_id" = v_due and y."completed_at" is null;
        perform "better_supabase"."sequence_place"(v_due);
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        update "better_supabase"."enrollment_steps" y set "due_at" = now() + interval '10 minutes'
        where y."enrollment_id" = v_due and y."completed_at" is null;
        update "better_supabase"."enrollments" x
        set "sequence_attempts" = x."sequence_attempts" + 1, "updated_at" = now()
        where x."id" = v_due
        returning * into v_row;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_row."id", 'sequenceId', v_row."sequence_id", 'organizationId', v_row."tenant_id",
          'accountId', coalesce(v_row."sequence_mail_account_id", v_sequence."mail_account_id"), 'threadId', v_row."sequence_mail_thread_id",
          'to', jsonb_build_object('address', v_row."sequence_address", 'name', v_row."sequence_name"),
          'step', v_step, 'variables', v_row."sequence_variables", 'attempt', v_row."sequence_attempts",
          'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"));
        exit;
      end if;
      if v_step ->> 'kind' = 'task' then
        perform "better_supabase"."create_work_item"(v_row."tenant_id", jsonb_build_object(
          'title', trim(v_step ->> 'title'),
          'body', v_step ->> 'body',
          'dueAt', case when v_step ? 'dueInMinutes' then now() + make_interval(mins => (v_step ->> 'dueInMinutes')::integer) end),
          case when v_row."enrolled_by" is null then '{}'::uuid[] else array[v_row."enrolled_by"] end);
      end if;
      perform "better_supabase"."sequence_step_done"(v_due, v_current);
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
  v_row "better_supabase"."enrollments";
  v_current text;
  v_next_run timestamptz;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."id" = sequence_step_sent.enrollment_id and x."sequence_id" is not null
  for update;
  if v_row."id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  select o."step", o."due_at" into v_current, v_next_run from "better_supabase"."enrollment_steps" o where o."enrollment_id" = v_row."id" and o."completed_at" is null limit 1;
  if v_row."status" <> 'active' or v_row."paused_at" is not null or v_current is distinct from sequence_step_sent.step then
    return "better_supabase"."sequence_member_json"(v_row."id");
  end if;
  if sequence_step_sent.message_id is not null then
    update "better_supabase"."enrollments" x
    set "sequence_mail_thread_id" = coalesce(x."sequence_mail_thread_id", y."thread_id"), "sequence_mail_account_id" = coalesce(x."sequence_mail_account_id", y."account_id"), "updated_at" = now()
    from "better_supabase"."mail_messages" y
    where x."id" = v_row."id" and y."id" = sequence_step_sent.message_id and y."tenant_id" = v_row."tenant_id";
  end if;
  perform "better_supabase"."sequence_step_done"(v_row."id", sequence_step_sent.step);
  return "better_supabase"."sequence_member_json"(v_row."id");
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
  v_row "better_supabase"."enrollments";
  v_current text;
  v_next_run timestamptz;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role runs sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."id" = sequence_step_failed.enrollment_id and x."sequence_id" is not null
  for update;
  if v_row."id" is null then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  select o."step", o."due_at" into v_current, v_next_run from "better_supabase"."enrollment_steps" o where o."enrollment_id" = v_row."id" and o."completed_at" is null limit 1;
  if v_row."status" <> 'active' or v_row."paused_at" is not null or v_current is distinct from sequence_step_failed.step then
    return "better_supabase"."sequence_member_json"(v_row."id");
  end if;
  update "better_supabase"."enrollments" x
  set "sequence_last_error" = left(coalesce(sequence_step_failed.error, 'send failed'), 2000), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."enrollment_steps" y
  set "due_at" = now() + make_interval(mins => 15 * greatest(v_row."sequence_attempts", 1))
  where y."enrollment_id" = v_row."id" and y."completed_at" is null;
  if v_row."sequence_attempts" >= 3 then
    perform "better_supabase"."sequence_exit"(v_row."id", 'failed');
  end if;
  return "better_supabase"."sequence_member_json"(v_row."id");
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
  v_run uuid;
begin
  for v_run in
    select x."id" from "better_supabase"."enrollments" x
    join "better_supabase"."sequences" y on y."id" = x."sequence_id"
    where x."tenant_id" = new."tenant_id" and x."status" = 'active' and y."exit_on_reply"
      and ((new."thread_id" is not null and x."sequence_mail_thread_id" = new."thread_id")
        or (new."from_address" is not null and lower(x."sequence_address") = lower(new."from_address")))
    for update of x
  loop
    perform "better_supabase"."sequence_exit"(v_run, 'replied');
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
drop policy if exists bsb_tenant_scope on "better_supabase"."sequences";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."sequences";
create policy bsb_tenant_scope_select on "better_supabase"."sequences" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('sequences.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."sequences";
create policy bsb_tenant_scope_insert on "better_supabase"."sequences" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."sequences";
create policy bsb_tenant_scope_update on "better_supabase"."sequences" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."sequences";
create policy bsb_tenant_scope_delete on "better_supabase"."sequences" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
