import type { BlockSqlContext } from "../context.ts";
import type { TaskNames } from "./tasks-functions.ts";

import { userGrant } from "../shared.ts";

/**
 * `create_task_with_sla`: `support.openTicket` as one atomic function (ADR
 * 1235). It creates the task with `create_task` and starts its SLA clocks with
 * `start_sla_clocks`, so each keeps its own permission check, hooks and events.
 * A failed clock start now rolls the task back. It needs the sla module;
 * without it the function is not written.
 */
export function createTaskWithSla(ctx: BlockSqlContext, n: TaskNames): string {
  if (!ctx.installed("sla")) {
    return "";
  }

  const fn = n.fn("create_task_with_sla");

  return `
-- Creates a work item (attrs and assignees as create_task) and starts its SLA
-- clocks on subject_type, at priority, in one transaction. Returns { task,
-- clocks }.
create or replace function ${fn}(tenant ${ctx.idType}, attrs jsonb, assignees uuid[], subject_type text, priority text default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_task jsonb;
  v_clocks jsonb;
begin
  v_task := ${n.fn("create_task")}(create_task_with_sla.tenant, create_task_with_sla.attrs, create_task_with_sla.assignees);
  v_clocks := ${ctx.of("sla").fn("start_sla_clocks")}(create_task_with_sla.subject_type, v_task ->> 'id', create_task_with_sla.priority);
  return jsonb_build_object('task', v_task, 'clocks', v_clocks);
end;
$$;
${userGrant(`${fn}(${ctx.idType}, jsonb, uuid[], text, text)`)}
`;
}
