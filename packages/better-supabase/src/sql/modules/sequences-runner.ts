import type { ModuleContext } from "../context.ts";

import {
  pageSize,
  SERVICE_CALLER,
  serviceGrant,
  triggerGrant,
} from "../shared.ts";
import { sequenceSql } from "./sequences-sql.ts";

/** How long a claimed email step waits for its result before it runs again. */
const LEASE_MINUTES = 10;

function runner(ctx: ModuleContext): string {
  const q = sequenceSql(ctx);
  const { fn, s, r, tasks } = q;
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
        perform ${tasks.fn("create_work_item")}(v_member.${r("tenant")}, jsonb_build_object(
          'title', trim(v_step ->> 'title'),
          'body', v_step ->> 'body',
          'dueAt', case when v_step ? 'dueInMinutes' then now() + make_interval(mins => (v_step ->> 'dueInMinutes')::integer) end),
          case when v_member.${r("enrolledBy")} is null then '{}'::uuid[] else array[v_member.${r("enrolledBy")}] end);
      end if;`;

  const forbidden = q.forbidden("only the service role runs sequences");

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
  v_due ${q.members};
  v_member ${q.members};
  v_sequence ${q.sequences};
  v_step jsonb;
  v_emails jsonb := '[]'::jsonb;
  v_ran integer := 0;
  v_turns integer;
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden}
  end if;
  for v_due in
    select x.* from ${q.members} x
    join ${q.sequences} y on y.${s("id")} = x.${r("sequence")}
    where x.${r("status")} = 'active' and x.${r("nextRunAt")} <= now() and y.${s("status")} = 'active'
    order by x.${r("nextRunAt")}, x.${r("enrollment")}
    limit ${pageSize("run_due_sequences.max_count", 50, 500)}
    for update of x skip locked
  loop
    v_turns := 0;
    loop
      v_turns := v_turns + 1;
      exit when v_turns > 60;
      select * into v_member from ${q.members} x where x.${r("enrollment")} = v_due.${r("enrollment")};
      exit when v_member.${r("status")} <> 'active' or v_member.${r("step")} is null or v_member.${r("nextRunAt")} > now();
      select * into v_sequence from ${q.sequences} x where x.${s("id")} = v_member.${r("sequence")};
      v_step := (select t.value from jsonb_array_elements(v_sequence.${s("steps")}) t where t.value ->> 'id' = v_member.${r("step")});
      if v_step is null then
        perform ${fn("sequence_place")}(v_member.${r("enrollment")});
        continue;
      end if;
      if v_step ->> 'kind' = 'email' then
        update ${q.members} x
        set ${r("attempts")} = x.${r("attempts")} + 1, ${r("nextRunAt")} = now() + interval '${String(LEASE_MINUTES)} minutes', ${r("updatedAt")} = now()
        where x.${r("enrollment")} = v_member.${r("enrollment")}
        returning * into v_member;
        v_emails := v_emails || jsonb_build_array(jsonb_build_object(
          'enrollmentId', v_member.${r("enrollment")}, 'sequenceId', v_member.${r("sequence")}, 'organizationId', v_member.${r("tenant")},
          'accountId', coalesce(v_member.${r("account")}, v_sequence.${s("account")}), 'threadId', v_member.${r("thread")},
          'to', jsonb_build_object('address', v_member.${r("address")}, 'name', v_member.${r("name")}),
          'step', v_step, 'variables', v_member.${r("variables")}, 'attempt', v_member.${r("attempts")},
          'subjectType', v_member.${r("subjectType")}, 'subjectId', v_member.${r("subjectId")}));
        exit;
      end if;${task}
      perform ${fn("sequence_step_done")}(v_member.${r("enrollment")}, v_member.${r("step")});
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
  v_member ${q.members};
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden}
  end if;
  select * into v_member from ${q.members} x where x.${r("enrollment")} = sequence_step_sent.enrollment_id for update;
  if v_member.${r("enrollment")} is null then
    ${q.memberMissing}
  end if;
  if v_member.${r("status")} <> 'active' or v_member.${r("step")} is distinct from sequence_step_sent.step then
    return ${fn("sequence_member_json")}(v_member.${r("enrollment")});
  end if;${threadOf(ctx)}
  perform ${fn("sequence_step_done")}(v_member.${r("enrollment")}, sequence_step_sent.step);
  return ${fn("sequence_member_json")}(v_member.${r("enrollment")});
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
  v_member ${q.members};
begin
  if not (${SERVICE_CALLER}) then
    ${forbidden}
  end if;
  select * into v_member from ${q.members} x where x.${r("enrollment")} = sequence_step_failed.enrollment_id for update;
  if v_member.${r("enrollment")} is null then
    ${q.memberMissing}
  end if;
  if v_member.${r("status")} <> 'active' or v_member.${r("step")} is distinct from sequence_step_failed.step then
    return ${fn("sequence_member_json")}(v_member.${r("enrollment")});
  end if;
  update ${q.members} x
  set ${r("lastError")} = left(coalesce(sequence_step_failed.error, 'send failed'), 2000),
    ${r("nextRunAt")} = now() + make_interval(mins => ${String(retryMinutes)} * greatest(x.${r("attempts")}, 1)),
    ${r("updatedAt")} = now()
  where x.${r("enrollment")} = v_member.${r("enrollment")}
  returning * into v_member;
  if v_member.${r("attempts")} >= ${String(maxAttempts)} then
    perform ${fn("sequence_exit")}(v_member.${r("enrollment")}, 'failed');
  end if;
  return ${fn("sequence_member_json")}(v_member.${r("enrollment")});
end;
$$;
${serviceGrant(`${fn("sequence_step_failed")}(uuid, text, text)`)}
`;
}

function threadOf(ctx: ModuleContext): string {
  const q = sequenceSql(ctx);
  const { r, mail } = q;

  if (mail === undefined) {
    return "";
  }

  const m = (column: string): string => mail.col("messages", column);

  return `
  if sequence_step_sent.message_id is not null then
    update ${q.members} x
    set ${r("thread")} = coalesce(x.${r("thread")}, y.${m("thread")}), ${r("account")} = coalesce(x.${r("account")}, y.${m("account")}), ${r("updatedAt")} = now()
    from ${mail.table("messages")} y
    where x.${r("enrollment")} = v_member.${r("enrollment")} and y.${m("id")} = sequence_step_sent.message_id and y.${m("tenant")} = v_member.${r("tenant")};
  end if;`;
}

function replies(ctx: ModuleContext): string {
  const q = sequenceSql(ctx);
  const { fn, s, r, mail } = q;

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
  v_member ${q.members};
begin
  for v_member in
    select x.* from ${q.members} x
    join ${q.sequences} y on y.${s("id")} = x.${r("sequence")}
    where x.${r("tenant")} = new.${m("tenant")} and x.${r("status")} in ('active', 'paused') and y.${s("exitOnReply")}
      and ((new.${m("thread")} is not null and x.${r("thread")} = new.${m("thread")})
        or (new.${m("fromAddress")} is not null and lower(x.${r("address")}) = lower(new.${m("fromAddress")})))
    for update of x
  loop
    perform ${fn("sequence_exit")}(v_member.${r("enrollment")}, 'replied');
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
export function sequenceRunner(ctx: ModuleContext): string {
  return `${runner(ctx)}${replies(ctx)}`;
}
