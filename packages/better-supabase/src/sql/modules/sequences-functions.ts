import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, pageSize, userGrant } from "../shared.ts";
import { sequenceSql } from "./sequences-sql.ts";

const UUID =
  "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";

const ADDRESS = "^[^@[:space:]]+@[^@[:space:]]+$";

/** The step ids of a steps array, in order. */
export const stepIds = (json: string): string =>
  `array(select t.value ->> 'id' from jsonb_array_elements(${json}) with ordinality as t(value, ord) order by t.ord)`;

/** Whether a steps array has an email step. */
export const sendsEmail = (json: string): string =>
  `exists (select 1 from jsonb_array_elements(${json}) t where t.value ->> 'kind' = 'email')`;

function stepsCheck(ctx: ModuleContext): string {
  const q = sequenceSql(ctx);
  const { fn, invalid } = q;

  return `-- Checks a steps array: [{ id, kind, ... }] where an email step has a
-- subject and text or html, a task step a title, and a wait step minutes.
create or replace function ${fn("sequence_steps_check")}(steps jsonb, mail boolean)
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
    ${invalid("steps must be an array")}
  end if;
  if jsonb_array_length(sequence_steps_check.steps) > 50 then
    ${invalid("a sequence has at most 50 steps")}
  end if;
  for v_step in select t.value from jsonb_array_elements(sequence_steps_check.steps) t loop
    if jsonb_typeof(v_step) <> 'object' then
      ${invalid("each step must be an object")}
    end if;
    v_id := v_step ->> 'id';
    if v_id is null or v_id !~ '^[a-z0-9][a-z0-9_-]{0,62}$' then
      ${invalid('step id: use lowercase letters, digits, "_" or "-"')}
    end if;
    if v_id = any(v_ids) then
      ${invalid("step ids must be unique")}
    end if;
    v_ids := v_ids || v_id;
    case v_step ->> 'kind'
      when 'wait' then
        if jsonb_typeof(v_step -> 'minutes') is distinct from 'number'
          or (v_step ->> 'minutes')::numeric <> trunc((v_step ->> 'minutes')::numeric)
          or (v_step ->> 'minutes')::numeric not between 1 and 525600 then
          ${invalid("a wait step waits 1 to 525600 whole minutes")}
        end if;
      when 'email' then
        if not sequence_steps_check.mail then
          ${invalid("email steps need the mail-sync block")}
        end if;
        if length(coalesce(trim(v_step ->> 'subject'), '')) not between 1 and 300 then
          ${invalid("an email step needs a subject of 1 to 300 characters")}
        end if;
        if coalesce(v_step ->> 'text', v_step ->> 'html') is null then
          ${invalid("an email step needs text or html")}
        end if;
        if length(coalesce(v_step ->> 'text', '')) + length(coalesce(v_step ->> 'html', '')) > 200000 then
          ${invalid("an email step's body is at most 200000 characters")}
        end if;
        if v_step ? 'track' and jsonb_typeof(v_step -> 'track') <> 'boolean' then
          ${invalid("track must be true or false")}
        end if;
        if v_step ? 'templateVersionId' and coalesce(v_step ->> 'templateVersionId', '') !~ '${UUID}' then
          ${invalid("templateVersionId must be a uuid")}
        end if;
      when 'task' then
        if length(coalesce(trim(v_step ->> 'title'), '')) not between 1 and 200 then
          ${invalid("a task step needs a title of 1 to 200 characters")}
        end if;
        if length(coalesce(v_step ->> 'body', '')) > 10000 then
          ${invalid("a task step's body is at most 10000 characters")}
        end if;
        if v_step ? 'dueInMinutes' and (jsonb_typeof(v_step -> 'dueInMinutes') is distinct from 'number'
          or (v_step ->> 'dueInMinutes')::numeric <> trunc((v_step ->> 'dueInMinutes')::numeric)
          or (v_step ->> 'dueInMinutes')::numeric not between 0 and 525600) then
          ${invalid("dueInMinutes must be 0 to 525600 whole minutes")}
        end if;
      else
        ${invalid("a step's kind must be email, task or wait")}
    end case;
  end loop;
end;
$$;
revoke execute on function ${fn("sequence_steps_check")}(jsonb, boolean) from public, anon, authenticated;
`;
}

function placement(ctx: ModuleContext): string {
  const q = sequenceSql(ctx);
  const { fn, s, r, e, d } = q;

  return `-- A recipient in a sequence with their completed steps.
create or replace function ${fn("sequence_member_json")}(enrollment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x.${r("enrollment")}, 'organizationId', x.${r("tenant")}, 'sequenceId', x.${r("sequence")},
    'subjectType', x.${r("subjectType")}, 'subjectId', x.${r("subjectId")}, 'address', x.${r("address")}, 'name', x.${r("name")},
    'accountId', x.${r("account")}, 'threadId', x.${r("thread")}, 'step', x.${r("step")}, 'nextRunAt', x.${r("nextRunAt")},
    'status', x.${r("status")}, 'exitReason', x.${r("exitReason")}, 'attempts', x.${r("attempts")}, 'lastError', x.${r("lastError")},
    'variables', x.${r("variables")}, 'enrolledBy', x.${r("enrolledBy")}, 'createdAt', x.${r("createdAt")}, 'updatedAt', x.${r("updatedAt")},
    'completedSteps', coalesce((select jsonb_agg(y.${d("step")} order by y.${d("completedAt")}, y.${d("step")}) from ${q.done} y where y.${d("enrollment")} = x.${r("enrollment")}), '[]'::jsonb))
  from ${q.members} x
  where x.${r("enrollment")} = sequence_member_json.enrollment_id;
$$;
revoke execute on function ${fn("sequence_member_json")}(uuid) from public, anon, authenticated;

-- Moves a recipient to their first step not done: a wait step runs once its
-- minutes pass, the others right away. With every step done the run
-- completes. A recipient already on that step keeps their schedule.
create or replace function ${fn("sequence_place")}(enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member ${q.members};
  v_steps jsonb;
  v_next jsonb;
begin
  select * into v_member from ${q.members} x where x.${r("enrollment")} = sequence_place.enrollment_id for update;
  if v_member.${r("enrollment")} is null or v_member.${r("status")} in ('completed', 'exited') then
    return;
  end if;
  select y.${s("steps")} into v_steps from ${q.sequences} y where y.${s("id")} = v_member.${r("sequence")};
  select t.value into v_next
  from jsonb_array_elements(coalesce(v_steps, '[]'::jsonb)) with ordinality as t(value, ord)
  where not exists (select 1 from ${q.done} z where z.${d("enrollment")} = v_member.${r("enrollment")} and z.${d("step")} = t.value ->> 'id')
  order by t.ord
  limit 1;
  if v_next is null then
    update ${q.members} x
    set ${r("status")} = 'completed', ${r("step")} = null, ${r("nextRunAt")} = null, ${r("attempts")} = 0, ${r("lastError")} = null, ${r("updatedAt")} = now()
    where x.${r("enrollment")} = v_member.${r("enrollment")}
    returning * into v_member;
    ${q.memberRecord("sequence_enrollment.completed", false)}
    return;
  end if;
  if (v_next ->> 'id') is not distinct from v_member.${r("step")} then
    return;
  end if;
  update ${q.members} x
  set ${r("step")} = v_next ->> 'id',
    ${r("nextRunAt")} = case when v_next ->> 'kind' = 'wait' then now() + make_interval(mins => (v_next ->> 'minutes')::integer) else now() end,
    ${r("attempts")} = 0, ${r("lastError")} = null, ${r("updatedAt")} = now()
  where x.${r("enrollment")} = v_member.${r("enrollment")};
end;
$$;
revoke execute on function ${fn("sequence_place")}(uuid) from public, anon, authenticated;

-- Ends a recipient's run (reason: replied, manual, failed or archived) and
-- cancels their enrollment; the completed steps stay.
create or replace function ${fn("sequence_exit")}(enrollment_id uuid, reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member ${q.members};
begin
  update ${q.members} x
  set ${r("status")} = 'exited', ${r("exitReason")} = sequence_exit.reason, ${r("nextRunAt")} = null, ${r("updatedAt")} = now()
  where x.${r("enrollment")} = sequence_exit.enrollment_id and x.${r("status")} in ('active', 'paused')
  returning * into v_member;
  if v_member.${r("enrollment")} is null then
    return;
  end if;
  update ${q.enrollments} x
  set ${e("status")} = 'cancelled', ${e("cancelledAt")} = now(), ${e("updatedAt")} = now()
  where x.${e("id")} = v_member.${r("enrollment")} and x.${e("status")} <> 'cancelled';
  if sequence_exit.reason = 'manual' then
    ${q.memberRecord("sequence_enrollment.exited", "removed from a sequence", "null::text", `v_member.${r("exitReason")}`)}
  else
    ${q.memberRecord("sequence_enrollment.exited", false, "null::text", `v_member.${r("exitReason")}`)}
  end if;
end;
$$;
revoke execute on function ${fn("sequence_exit")}(uuid, text) from public, anon, authenticated;

-- Marks the recipient's current step done and moves them on.
create or replace function ${fn("sequence_step_done")}(enrollment_id uuid, step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member ${q.members};
begin
  perform ${fn("enrollment_mark")}(sequence_step_done.enrollment_id, sequence_step_done.step, true, null);
  select * into v_member from ${q.members} x where x.${r("enrollment")} = sequence_step_done.enrollment_id;
  ${q.memberRecord("sequence_enrollment.step_completed", false, "sequence_step_done.step")}
  perform ${fn("sequence_place")}(sequence_step_done.enrollment_id);
end;
$$;
revoke execute on function ${fn("sequence_step_done")}(uuid, text) from public, anon, authenticated;

-- Gives every running recipient of a sequence its current steps and moves
-- them to their first step not done.
create or replace function ${fn("sequence_resync")}(sequence_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence ${q.sequences};
  v_member ${q.members};
begin
  select * into v_sequence from ${q.sequences} x where x.${s("id")} = sequence_resync.sequence_id;
  for v_member in
    select * from ${q.members} x
    where x.${r("sequence")} = sequence_resync.sequence_id and x.${r("status")} in ('active', 'paused')
    for update
  loop
    perform ${fn("enrollment_ensure")}(v_sequence.${s("tenant")}, ${q.program(`v_sequence.${s("id")}`)}, v_sequence.${s("version")}, ${stepIds(`v_sequence.${s("steps")}`)},
      v_member.${r("subjectType")}, v_member.${r("subjectId")}, null);
    perform ${fn("sequence_place")}(v_member.${r("enrollment")});
  end loop;
end;
$$;
revoke execute on function ${fn("sequence_resync")}(uuid) from public, anon, authenticated;
`;
}

function authoring(ctx: ModuleContext): string {
  const q = sequenceSql(ctx);
  const { fn, s, r, mail } = q;

  const counts = (id: string): string =>
    `(select jsonb_build_object('active', count(*) filter (where m.${r("status")} = 'active'), 'paused', count(*) filter (where m.${r("status")} = 'paused'),
      'completed', count(*) filter (where m.${r("status")} = 'completed'), 'exited', count(*) filter (where m.${r("status")} = 'exited'),
      'replied', count(*) filter (where m.${r("exitReason")} = 'replied'))
    from ${q.members} m where m.${r("sequence")} = ${id})`;

  const mailboxCheck =
    mail === undefined
      ? `if v_account is not null then
    ${q.invalid("accountId needs the mail-sync block")}
  end if;`
      : `if v_account is not null and not exists (
    select 1 from ${mail.table("accounts")} k
    where k.${mail.col("accounts", "id")} = v_account and k.${mail.col("accounts", "tenant")} = save_sequence.tenant
      and k.${mail.col("accounts", "status")} <> 'disconnected'
  ) then
    ${q.invalid("accountId must be a connected mailbox of this organization")}
  end if;`;

  const record = (type: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${s("tenant")}, 'id', v_row.${s("id")}, 'key', v_row.${s("key")}, 'status', v_row.${s("status")})`,
      subject: `'sequences/' || v_row.${s("id")}::text`,
      tenant: `v_row.${s("tenant")}`,
      audit: {
        category: "data",
        targetType: "sequence",
        recordId: `v_row.${s("id")}::text`,
        targetLabel: `v_row.${s("name")}`,
        summary: `'${summary}'`,
      },
    });

  return `-- Creates or changes a sequence. sequence is { id?, key, name,
-- description, status, exitOnReply, accountId, steps }; keys left out keep
-- their value. Changing the steps raises the version and moves running
-- recipients onto the new steps. Archiving ends every run.
create or replace function ${fn("save_sequence")}(tenant ${ctx.idType}, sequence jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old ${q.sequences};
  v_row ${q.sequences};
  v_key text;
  v_name text;
  v_description text;
  v_status text;
  v_exit boolean;
  v_account uuid;
  v_steps jsonb;
  v_member ${q.members};
begin
  if not ${q.allowed("save_sequence.tenant", q.manage)} then
    ${q.forbidden("not allowed to manage sequences")}
  end if;
  if save_sequence.sequence is null or jsonb_typeof(save_sequence.sequence) <> 'object' then
    ${q.invalid("sequence must be an object")}
  end if;
  v_id := nullif(save_sequence.sequence ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${q.sequences} x
    where x.${s("id")} = v_id and x.${s("tenant")} = save_sequence.tenant
    for update;
    if v_old.${s("id")} is null then
      ${q.sequenceMissing}
    end if;
  end if;
  v_key := coalesce(save_sequence.sequence ->> 'key', v_old.${s("key")});
  v_name := trim(coalesce(save_sequence.sequence ->> 'name', v_old.${s("name")}));
  v_description := case when save_sequence.sequence ? 'description'
    then nullif(trim(save_sequence.sequence ->> 'description'), '') else v_old.${s("description")} end;
  v_status := coalesce(save_sequence.sequence ->> 'status', v_old.${s("status")}, 'draft');
  v_exit := case when save_sequence.sequence ? 'exitOnReply'
    then (save_sequence.sequence ->> 'exitOnReply')::boolean else coalesce(v_old.${s("exitOnReply")}, true) end;
  v_account := case when save_sequence.sequence ? 'accountId'
    then nullif(save_sequence.sequence ->> 'accountId', '')::uuid else v_old.${s("account")} end;
  v_steps := case when save_sequence.sequence ? 'steps'
    then save_sequence.sequence -> 'steps' else coalesce(v_old.${s("steps")}, '[]'::jsonb) end;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    ${q.invalid('key: use lowercase letters, digits or "-", starting with a letter')}
  end if;
  if v_old.${s("id")} is not null and v_key <> v_old.${s("key")} then
    ${q.invalid("a sequence's key can't change")}
  end if;
  if v_name is null or length(v_name) not between 1 and 200 then
    ${q.invalid("name must be 1 to 200 characters")}
  end if;
  if length(v_description) > 2000 then
    ${q.invalid("description must be at most 2000 characters")}
  end if;
  if v_status not in ('draft', 'active', 'paused', 'archived') then
    ${q.invalid("status must be draft, active, paused or archived")}
  end if;
  if v_exit is null then
    ${q.invalid("exitOnReply must be true or false")}
  end if;
  perform ${fn("sequence_steps_check")}(v_steps, ${mail === undefined ? "false" : "true"});
  if v_status = 'active' and jsonb_array_length(v_steps) = 0 then
    ${q.invalid("an active sequence needs at least one step")}
  end if;
  ${mailboxCheck}
  if v_old.${s("id")} is null then
    insert into ${q.sequences} (${s("tenant")}, ${s("key")}, ${s("name")}, ${s("description")}, ${s("status")}, ${s("exitOnReply")}, ${s("account")}, ${s("steps")}, ${s("createdBy")})
    values (save_sequence.tenant, v_key, v_name, v_description, v_status, v_exit, v_account, v_steps, auth.uid())
    returning * into v_row;
  else
    update ${q.sequences} x
    set ${s("name")} = v_name, ${s("description")} = v_description, ${s("status")} = v_status, ${s("exitOnReply")} = v_exit,
      ${s("account")} = v_account, ${s("steps")} = v_steps,
      ${s("version")} = x.${s("version")} + case when x.${s("steps")} is distinct from v_steps then 1 else 0 end,
      ${s("updatedAt")} = now()
    where x.${s("id")} = v_old.${s("id")}
    returning * into v_row;
    if v_old.${s("steps")} is distinct from v_row.${s("steps")} then
      perform ${fn("sequence_resync")}(v_row.${s("id")});
    end if;
    if v_row.${s("status")} = 'archived' and v_old.${s("status")} <> 'archived' then
      for v_member in
        select * from ${q.members} x
        where x.${r("sequence")} = v_row.${s("id")} and x.${r("status")} in ('active', 'paused')
      loop
        perform ${fn("sequence_exit")}(v_member.${r("enrollment")}, 'archived');
      end loop;
    end if;
  end if;
  ${record("sequence.saved", "saved a sequence")}
  return ${q.sequenceJson("v_row")} || jsonb_build_object('counts', ${counts(`v_row.${s("id")}`)});
end;
$$;
${userGrant(`${fn("save_sequence")}(${ctx.idType}, jsonb)`)}

-- An organization's sequences with their recipient counts, by name. status
-- filters; without it archived sequences stay out.
create or replace function ${fn("list_sequences")}(tenant ${ctx.idType}, status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("list_sequences.tenant", q.read)} then
    ${q.forbidden("not allowed to read sequences")}
  end if;
  return coalesce((
    select jsonb_agg(${q.sequenceJson("x")} || jsonb_build_object('counts', ${counts(`x.${s("id")}`)}) order by x.${s("name")}, x.${s("id")})
    from ${q.sequences} x
    where x.${s("tenant")} = list_sequences.tenant
      and (case when list_sequences.status is null then x.${s("status")} <> 'archived' else x.${s("status")} = list_sequences.status end)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_sequences")}(${ctx.idType}, text)`)}

-- One sequence with its recipient counts.
create or replace function ${fn("get_sequence")}(sequence_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.sequences};
begin
  select * into v_row from ${q.sequences} x where x.${s("id")} = get_sequence.sequence_id;
  if v_row.${s("id")} is null or not ${q.allowed(`v_row.${s("tenant")}`, q.read)} then
    ${q.sequenceMissing}
  end if;
  return ${q.sequenceJson("v_row")} || jsonb_build_object('counts', ${counts(`v_row.${s("id")}`)});
end;
$$;
${userGrant(`${fn("get_sequence")}(uuid)`)}

-- Deletes a sequence with its enrollments; false when there was none.
create or replace function ${fn("delete_sequence")}(sequence_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.sequences};
begin
  select * into v_row from ${q.sequences} x where x.${s("id")} = delete_sequence.sequence_id for update;
  if v_row.${s("id")} is null then
    return false;
  end if;
  if not ${q.allowed(`v_row.${s("tenant")}`, q.manage)} then
    ${q.forbidden("not allowed to manage sequences")}
  end if;
  delete from ${q.enrollments} x where x.${q.e("tenant")} = v_row.${s("tenant")} and x.${q.e("program")} = ${q.program(`v_row.${s("id")}`)};
  delete from ${q.sequences} x where x.${s("id")} = v_row.${s("id")};
  ${record("sequence.deleted", "deleted a sequence")}
  return true;
end;
$$;
${userGrant(`${fn("delete_sequence")}(uuid)`)}
`;
}

function enrolling(ctx: ModuleContext): string {
  const q = sequenceSql(ctx);
  const { fn, s, r, e, d, mail, parties } = q;
  const a = (column: string): string => mail!.col("accounts", column);

  const person =
    parties === undefined
      ? ""
      : `if enroll_in_sequence.subject_type = ${sqlString(parties.naming.rename("person"))} then
    select y.${parties.col("people", "email")}, y.${parties.col("people", "name")} into v_email, v_label
    from ${parties.table("people")} y
    where y.${parties.col("people", "id")}::text = enroll_in_sequence.subject_id and y.${parties.col("people", "tenant")} = v_sequence.${s("tenant")};
    if not found then
      ${q.invalid("no such person in this organization")}
    end if;
    v_address := coalesce(v_address, v_email);
    v_name := coalesce(v_name, v_label);
  end if;`;

  const mailbox =
    mail === undefined
      ? `if v_account is not null then
    ${q.invalid("accountId needs the mail-sync block")}
  end if;`
      : `if v_account is null then
    v_account := coalesce(v_sequence.${s("account")}, (
      select k.${a("id")} from ${mail.table("accounts")} k
      where k.${a("tenant")} = v_sequence.${s("tenant")} and k.${a("user")} = auth.uid() and k.${a("status")} = 'active'
      order by k.${a("createdAt")}, k.${a("id")}
      limit 1));
  else
    select k.${a("user")} into v_owner from ${mail.table("accounts")} k
    where k.${a("id")} = v_account and k.${a("tenant")} = v_sequence.${s("tenant")} and k.${a("status")} <> 'disconnected';
    if not found then
      ${q.invalid("accountId must be a connected mailbox of this organization")}
    end if;
    if v_owner is distinct from auth.uid() and not ${q.allowed(`v_sequence.${s("tenant")}`, q.manage)} then
      ${q.forbidden("only a sequence manager sends from another user's mailbox")}
    end if;
  end if;
  if v_account is null and ${sendsEmail(`v_sequence.${s("steps")}`)} then
    ${q.invalid("connect a mailbox or set one on the sequence to send its email steps")}
  end if;`;

  return `-- Enrolls a record (subject_type, subject_id) in an active sequence. attrs
-- is { address, name, accountId, variables }: a person's email and name fill
-- address and name when left out, and the mailbox defaults to the
-- sequence's, then the caller's. A finished or exited run starts over.
create or replace function ${fn("enroll_in_sequence")}(sequence_id uuid, subject_type text, subject_id text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_sequence ${q.sequences};
  v_row ${q.enrollments};
  v_member ${q.members};
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
  select * into v_sequence from ${q.sequences} x where x.${s("id")} = enroll_in_sequence.sequence_id;
  if v_sequence.${s("id")} is null or not (${q.allowed(`v_sequence.${s("tenant")}`, q.read)} or ${q.allowed(`v_sequence.${s("tenant")}`, q.enroll)}) then
    ${q.sequenceMissing}
  end if;
  if not ${q.allowed(`v_sequence.${s("tenant")}`, q.enroll)} then
    ${q.forbidden("not allowed to enroll in sequences")}
  end if;
  if v_sequence.${s("status")} <> 'active' then
    ${fail("SEQUENCE_NOT_ACTIVE", "only an active sequence takes enrollments", "55000")}
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    ${q.invalid("attrs must be an object")}
  end if;
  if enroll_in_sequence.subject_type is null or enroll_in_sequence.subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${q.invalid("subject_type: use lowercase letters, digits or _")}
  end if;
  if enroll_in_sequence.subject_id is null or length(enroll_in_sequence.subject_id) not between 1 and 200 then
    ${q.invalid("subject_id must be 1 to 200 characters")}
  end if;
  v_address := nullif(trim(v_attrs ->> 'address'), '');
  v_name := nullif(trim(v_attrs ->> 'name'), '');
  v_account := nullif(v_attrs ->> 'accountId', '')::uuid;
  v_variables := coalesce(v_attrs -> 'variables', '{}'::jsonb);
  ${person}
  if v_address is not null and (length(v_address) > 320 or v_address !~ '${ADDRESS}') then
    ${q.invalid("address must be an email address")}
  end if;
  if length(v_name) > 200 then
    ${q.invalid("name must be at most 200 characters")}
  end if;
  if jsonb_typeof(v_variables) <> 'object' or length(v_variables::text) > 10000 then
    ${q.invalid("variables must be an object of at most 10000 characters")}
  end if;
  if v_address is null and ${sendsEmail(`v_sequence.${s("steps")}`)} then
    ${q.invalid("the recipient needs an email address for the sequence's email steps")}
  end if;
  ${mailbox}
  select * into v_row from ${q.enrollments} x
  where x.${e("tenant")} = v_sequence.${s("tenant")} and x.${e("program")} = ${q.program(`v_sequence.${s("id")}`)}
    and x.${e("subjectType")} = enroll_in_sequence.subject_type and x.${e("subjectId")} = enroll_in_sequence.subject_id
  for update;
  if v_row.${e("id")} is not null then
    select * into v_member from ${q.members} x where x.${r("enrollment")} = v_row.${e("id")} for update;
    if v_member.${r("status")} in ('active', 'paused') then
      return ${fn("sequence_member_json")}(v_row.${e("id")});
    end if;
    -- Starting over: clearing the steps makes enrollment_ensure take the
    -- current ones, with none done.
    delete from ${q.done} x where x.${d("enrollment")} = v_row.${e("id")};
    update ${q.enrollments} x
    set ${e("status")} = 'active', ${e("cancelledAt")} = null, ${e("completedAt")} = null, ${e("enrolledBy")} = auth.uid(),
      ${e("enrolledAt")} = now(), ${e("steps")} = '{}'
    where x.${e("id")} = v_row.${e("id")};
  end if;
  v_id := ${fn("enrollment_ensure")}(v_sequence.${s("tenant")}, ${q.program(`v_sequence.${s("id")}`)}, v_sequence.${s("version")}, ${stepIds(`v_sequence.${s("steps")}`)},
    enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, auth.uid());
  insert into ${q.members} (${r("enrollment")}, ${r("tenant")}, ${r("sequence")}, ${r("subjectType")}, ${r("subjectId")}, ${r("address")}, ${r("name")},
    ${r("account")}, ${r("variables")}, ${r("enrolledBy")})
  values (v_id, v_sequence.${s("tenant")}, v_sequence.${s("id")}, enroll_in_sequence.subject_type, enroll_in_sequence.subject_id, v_address, v_name,
    v_account, v_variables, auth.uid())
  on conflict (${r("enrollment")}) do update
  set ${r("address")} = excluded.${r("address")}, ${r("name")} = excluded.${r("name")}, ${r("account")} = excluded.${r("account")},
    ${r("variables")} = excluded.${r("variables")}, ${r("enrolledBy")} = excluded.${r("enrolledBy")}, ${r("status")} = 'active',
    ${r("exitReason")} = null, ${r("step")} = null, ${r("nextRunAt")} = null, ${r("thread")} = null, ${r("attempts")} = 0,
    ${r("lastError")} = null, ${r("updatedAt")} = now();
  perform ${fn("sequence_place")}(v_id);
  select * into v_member from ${q.members} x where x.${r("enrollment")} = v_id;
  ${q.memberRecord("sequence_enrollment.created", "enrolled in a sequence")}
  return ${fn("sequence_member_json")}(v_id);
end;
$$;
${userGrant(`${fn("enroll_in_sequence")}(uuid, text, text, jsonb)`)}

-- Pauses, resumes or exits a recipient's run (action: pause, resume, exit).
create or replace function ${fn("change_sequence_enrollment")}(enrollment_id uuid, action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_member ${q.members};
begin
  select * into v_member from ${q.members} x where x.${r("enrollment")} = change_sequence_enrollment.enrollment_id for update;
  if v_member.${r("enrollment")} is null or not (${q.allowed(`v_member.${r("tenant")}`, q.read)} or ${q.allowed(`v_member.${r("tenant")}`, q.enroll)}) then
    ${q.memberMissing}
  end if;
  if not ${q.allowed(`v_member.${r("tenant")}`, q.enroll)} then
    ${q.forbidden("not allowed to change sequence enrollments")}
  end if;
  case change_sequence_enrollment.action
    when 'pause' then
      if v_member.${r("status")} <> 'active' then
        ${q.invalid("only an active run can be paused")}
      end if;
      update ${q.members} x set ${r("status")} = 'paused', ${r("updatedAt")} = now()
      where x.${r("enrollment")} = v_member.${r("enrollment")}
      returning * into v_member;
      ${q.memberRecord("sequence_enrollment.paused", "paused a sequence run")}
    when 'resume' then
      if v_member.${r("status")} <> 'paused' then
        ${q.invalid("only a paused run can be resumed")}
      end if;
      update ${q.members} x set ${r("status")} = 'active', ${r("updatedAt")} = now()
      where x.${r("enrollment")} = v_member.${r("enrollment")}
      returning * into v_member;
      ${q.memberRecord("sequence_enrollment.resumed", "resumed a sequence run")}
    when 'exit' then
      if v_member.${r("status")} not in ('active', 'paused') then
        ${q.invalid("only an active or paused run can be exited")}
      end if;
      perform ${fn("sequence_exit")}(v_member.${r("enrollment")}, 'manual');
    else
      ${q.invalid("action must be pause, resume or exit")}
  end case;
  return ${fn("sequence_member_json")}(v_member.${r("enrollment")});
end;
$$;
${userGrant(`${fn("change_sequence_enrollment")}(uuid, text)`)}

-- An organization's sequence recipients, newest first. filter is
-- { sequence, subjectType, subjectId, status, limit, before }: before is a
-- createdAt from the previous page.
create or replace function ${fn("list_sequence_enrollments")}(tenant ${ctx.idType}, filter jsonb default '{}')
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
  if not (${q.allowed("list_sequence_enrollments.tenant", q.read)} or ${q.allowed("list_sequence_enrollments.tenant", q.enroll)}) then
    ${q.forbidden("not allowed to read sequences")}
  end if;
  if jsonb_typeof(v_filter) <> 'object' then
    ${q.invalid("filter must be an object")}
  end if;
  return coalesce((
    select jsonb_agg(${fn("sequence_member_json")}(y.${r("enrollment")}) order by y.${r("createdAt")} desc, y.${r("enrollment")} desc)
    from (
      select x.${r("enrollment")}, x.${r("createdAt")}
      from ${q.members} x
      where x.${r("tenant")} = list_sequence_enrollments.tenant
        and (v_parent is null or x.${r("sequence")} = v_parent)
        and (v_filter ->> 'subjectType' is null or x.${r("subjectType")} = v_filter ->> 'subjectType')
        and (v_filter ->> 'subjectId' is null or x.${r("subjectId")} = v_filter ->> 'subjectId')
        and (v_filter ->> 'status' is null or x.${r("status")} = v_filter ->> 'status')
        and (v_filter ->> 'before' is null or x.${r("createdAt")} < (v_filter ->> 'before')::timestamptz)
      order by x.${r("createdAt")} desc, x.${r("enrollment")} desc
      limit ${pageSize("(v_filter ->> 'limit')::integer", 50, 200)}
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_sequence_enrollments")}(${ctx.idType}, jsonb)`)}
`;
}

/** The sequences module's authoring and enrollment functions. */
export function sequenceFunctions(ctx: ModuleContext): string {
  return `${stepsCheck(ctx)}
${placement(ctx)}
${authoring(ctx)}
${enrolling(ctx)}`;
}
