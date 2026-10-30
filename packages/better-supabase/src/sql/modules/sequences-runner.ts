import type { BlockSqlContext } from "../context.ts";

import {
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  triggerGrant,
} from "../shared.ts";
import { sequenceSql } from "./sequences-sql.ts";

/** How long a claimed email step waits for its result before it runs again. */
const LEASE_MINUTES = 10;

function runner(ctx: BlockSqlContext): string {
  const q = sequenceSql(ctx);
  const { fn, s, r, e, d, tasks } = q;
  const maxAttempts = ctx.number("maxAttempts", 3);
  const retryMinutes = ctx.number("retryMinutes", 15);

  if (!Number.isInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 20) {
    throw new TypeError(
      "blocks.sequences.options.maxAttempts must be a whole number from 1 to 20",
    );
  }

  if (
    !Number.isInteger(retryMinutes) ||
    retryMinutes < 1 ||
    retryMinutes > 1440
  ) {
    throw new TypeError(
      "blocks.sequences.options.retryMinutes must be a whole number from 1 to 1440",
    );
  }

  const task =
    tasks === undefined
      ? ""
      : `
      if v_step ->> 'kind' = 'task' then
        perform ${tasks.fn("create_task")}(v_row.${e("tenant")}, jsonb_build_object(
          'title', trim(v_step ->> 'title'),
          'body', v_step ->> 'body',
          'dueAt', case when v_step ? 'dueInMinutes' then now() + make_interval(mins => (v_step ->> 'dueInMinutes')::integer) end),
          case when v_row.${e("enrolledBy")} is null then '{}'::uuid[] else array[v_row.${e("enrolledBy")}] end);
      end if;`;

  const forbidden = q.forbidden("only the service role runs sequences");

  // Loads the run into v_row; a stale result, for a run that moved on or
  // stopped, returns it unchanged.
  const claimed = (
    name: string,
  ): string => `select * into v_row from ${q.enrollments} x
  where x.${e("id")} = ${name}.enrollment_id and x.${r("sequence")} is not null
  for update;
  if v_row.${e("id")} is null then
    ${q.memberMissing}
  end if;
  ${q.openStep(`v_row.${e("id")}`, "v_current, v_next_run")}
  if v_row.${e("status")} <> 'active' or v_row.${e("pausedAt")} is not null or v_current is distinct from ${name}.step then
    return ${fn("sequence_member_json")}(v_row.${e("id")});
  end if;`;

  return `-- Runs the steps that are due, oldest first: wait steps finish, task steps
-- create a work item for whoever enrolled the recipient, and email steps
-- are claimed for ${String(LEASE_MINUTES)} minutes and returned for the caller to send. Call
-- sequence_step_sent or sequence_step_failed with each result. Returns
-- { ran, emails: [{ enrollmentId, sequenceId, organizationId, accountId,
-- threadId, to, step, variables, attempt, subjectType, subjectId }] }.
create or replace function ${fn("run_due_sequences")}(max_count integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_due uuid;
  v_row ${q.enrollments};
  v_sequence ${q.sequences};
  v_current text;
  v_next_run timestamptz;
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden}
  end if;
  for v_due in
    select x.${e("id")} from ${q.enrollments} x
    join ${q.done} o on o.${d("enrollment")} = x.${e("id")} and o.${d("completedAt")} is null
    join ${q.sequences} y on y.${s("id")} = x.${r("sequence")}
    where o.${d("dueAt")} <= now() and x.${e("status")} = 'active' and x.${e("pausedAt")} is null and y.${s("status")} = 'active'
    order by o.${d("dueAt")}, x.${e("id")}
    limit ${pageSize("run_due_sequences.max_count", 50, 500)}
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_row from ${q.enrollments} x where x.${e("id")} = v_due;
      v_current := null;
      v_next_run := null;
      ${q.openStep("v_due", "v_current, v_next_run")}
      exit when v_row.${e("status")} <> 'active' or v_row.${e("pausedAt")} is not null or v_current is null or v_next_run > now();
      select * into v_sequence from ${q.sequences} x where x.${s("id")} = v_row.${r("sequence")};
      v_step := (select t.value from jsonb_array_elements(v_sequence.${s("steps")}) t where t.value ->> 'id' = v_current);
      if v_step is null then
        delete from ${q.done} y where y.${d("enrollment")} = v_due and y.${d("completedAt")} is null;
        perform ${fn("sequence_place")}(v_due);
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        update ${q.done} y set ${d("dueAt")} = now() + interval '${String(LEASE_MINUTES)} minutes'
        where y.${d("enrollment")} = v_due and y.${d("completedAt")} is null;
        update ${q.enrollments} x
        set ${r("attempts")} = x.${r("attempts")} + 1, ${e("updatedAt")} = now()
        where x.${e("id")} = v_due
        returning * into v_row;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_row.${e("id")}, 'sequenceId', v_row.${r("sequence")}, 'organizationId', v_row.${e("tenant")},
          'accountId', coalesce(v_row.${r("account")}, v_sequence.${s("account")}), 'threadId', v_row.${r("thread")},
          'to', jsonb_build_object('address', v_row.${r("address")}, 'name', v_row.${r("name")}),
          'step', v_step, 'variables', v_row.${r("variables")}, 'attempt', v_row.${r("attempts")},
          'subjectType', v_row.${e("subjectType")}, 'subjectId', v_row.${e("subjectId")}));
        exit;
      end if;${task}
      perform ${fn("sequence_step_done")}(v_due, v_current);
      v_ran := v_ran + 1;
    end loop;
  end loop;
  return jsonb_build_object('ran', v_ran, 'emails', v_emails);
end;
$$;
${serviceGrant(`${fn("run_due_sequences")}(integer)`)}

-- Records that a claimed email step went out as message_id (a mail-sync
-- message, or null): later emails reply on its thread. A stale result, for
-- a run that moved on, changes nothing.
create or replace function ${fn("sequence_step_sent")}(enrollment_id uuid, step text, message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.enrollments};
  v_current text;
  v_next_run timestamptz;
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden}
  end if;
  ${claimed("sequence_step_sent")}${threadOf(ctx)}
  perform ${fn("sequence_step_done")}(v_row.${e("id")}, sequence_step_sent.step);
  return ${fn("sequence_member_json")}(v_row.${e("id")});
end;
$$;
${serviceGrant(`${fn("sequence_step_sent")}(uuid, text, uuid)`)}

-- Records that a claimed email step failed to send: it runs again after
-- ${String(retryMinutes)} minutes times the attempts, and the run exits as failed after
-- ${String(maxAttempts)} attempts.
create or replace function ${fn("sequence_step_failed")}(enrollment_id uuid, step text, error text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${q.enrollments};
  v_current text;
  v_next_run timestamptz;
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden}
  end if;
  ${claimed("sequence_step_failed")}
  update ${q.enrollments} x
  set ${r("lastError")} = left(coalesce(sequence_step_failed.error, 'send failed'), 2000), ${e("updatedAt")} = now()
  where x.${e("id")} = v_row.${e("id")}
  returning * into v_row;
  update ${q.done} y
  set ${d("dueAt")} = now() + make_interval(mins => ${String(retryMinutes)} * greatest(v_row.${r("attempts")}, 1))
  where y.${d("enrollment")} = v_row.${e("id")} and y.${d("completedAt")} is null;
  if v_row.${r("attempts")} >= ${String(maxAttempts)} then
    perform ${fn("sequence_exit")}(v_row.${e("id")}, 'failed');
  end if;
  return ${fn("sequence_member_json")}(v_row.${e("id")});
end;
$$;
${serviceGrant(`${fn("sequence_step_failed")}(uuid, text, text)`)}
`;
}

function threadOf(ctx: BlockSqlContext): string {
  const q = sequenceSql(ctx);
  const { r, e, mail } = q;

  if (mail === undefined) {
    return "";
  }

  const m = (column: string): string => mail.col("messages", column);

  return `
  if sequence_step_sent.message_id is not null then
    update ${q.enrollments} x
    set ${r("thread")} = coalesce(x.${r("thread")}, y.${m("thread")}), ${r("account")} = coalesce(x.${r("account")}, y.${m("account")}), ${e("updatedAt")} = now()
    from ${mail.table("messages")} y
    where x.${e("id")} = v_row.${e("id")} and y.${m("id")} = sequence_step_sent.message_id and y.${m("tenant")} = v_row.${e("tenant")};
  end if;`;
}

function replies(ctx: BlockSqlContext): string {
  const q = sequenceSql(ctx);
  const { fn, s, r, e, mail } = q;

  if (mail === undefined) {
    return "";
  }

  const m = (column: string): string => mail.col("messages", column);
  const trigger = ctx.trigger("replied");

  return `
-- An inbound message on a recipient's thread, or from their address, ends
-- their run in every sequence that exits on reply.
create or replace function ${fn("sequence_mail_replied")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run uuid;
begin
  for v_run in
    select x.${e("id")} from ${q.enrollments} x
    join ${q.sequences} y on y.${s("id")} = x.${r("sequence")}
    where x.${e("tenant")} = new.${m("tenant")} and x.${e("status")} = 'active' and y.${s("exitOnReply")}
      and ((new.${m("thread")} is not null and x.${r("thread")} = new.${m("thread")})
        or (new.${m("fromAddress")} is not null and lower(x.${r("address")}) = lower(new.${m("fromAddress")})))
    for update of x
  loop
    perform ${fn("sequence_exit")}(v_run, 'replied');
  end loop;
  return null;
end;
$$;
${triggerGrant(`${fn("sequence_mail_replied")}()`)}
drop trigger if exists ${trigger} on ${mail.table("messages")};
create trigger ${trigger}
  after insert on ${mail.table("messages")}
  for each row when (new.${m("direction")} = 'inbound')
  execute function ${fn("sequence_mail_replied")}();
`;
}

/** The sequences module's runner functions and the reply trigger. */
export function sequenceRunner(ctx: BlockSqlContext): string {
  return `${runner(ctx)}${replies(ctx)}`;
}
