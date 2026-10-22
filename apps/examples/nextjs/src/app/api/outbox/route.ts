import type {
  RuleFieldSetter,
  RuleSubjectContext,
} from "better-supabase/blocks/automations";

import { dbError, err } from "better-supabase";
import {
  createRuleDispatcher,
  createRuleSink,
  createAutomationsAdmin,
  rpcTransport,
  setFieldAction,
} from "better-supabase/blocks/automations";
import { conversationToWorkItem, createFlows } from "better-supabase/flows";
import { connection } from "next/server";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const TASK_STATUSES = ["todo", "doing", "done"] as const;

type TaskStatus = (typeof TASK_STATUSES)[number];

const isTaskStatus = (value: unknown): value is TaskStatus =>
  TASK_STATUSES.some((status) => status === value);

const TaskEventPayload = v.object({ id: v.string() });

/** A rule's `set_field` action on a task may only move its status. */
const setTaskField: RuleFieldSetter = async (write) => {
  const status = write.value;

  if (
    write.subjectType !== "task" ||
    write.field !== "status" ||
    !isTaskStatus(status)
  ) {
    return err(
      dbError(
        "invalid_request",
        `A rule can set only a task's status to todo, doing or done, not ${write.field}`,
      ),
    );
  }

  return bsb.admin().tasks.update(write.subjectId, { status });
};

/**
 * Runs the rules on the `task.created`, `task.updated` and `task.deleted`
 * events the `tasks` app table writes to the outbox, and the flows on the
 * inbox's events. Call it every minute from a cron (Vercel Cron sends
 * `Authorization: Bearer $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  // Without a request-time API, Next.js runs this handler at build time.
  await connection();
  const admin = bsb.admin();
  const schema = blockConfig.automations.api;

  const sink = createRuleSink<RuleSubjectContext>({
    rules: createAutomationsAdmin({
      transport: rpcTransport(admin.$client, { schema }),
      schema,
    }),
    dispatcher: createRuleDispatcher({
      handlers: { set_field: setFieldAction(setTaskField) },
    }),
    load: async (event) => {
      const payload = v.safeParse(TaskEventPayload, event.payload);

      if (!event.type.startsWith("task.") || !payload.success) {
        return;
      }

      const { id } = payload.output;

      const task = await admin.tasks
        .get(id, {
          select: ["id", "organizationId", "title", "status", "dueOn"],
          optional: true,
        })
        .orThrow();

      if (task === null) {
        return;
      }

      return {
        organizationId: task.organizationId,
        subjectType: "task",
        subjectId: task.id,
        subject: task,
        context: {
          organizationId: task.organizationId,
          subjectType: "task",
          subjectId: task.id,
          eventId: event.id,
          payload: task,
        },
      };
    },
  });

  // Opens a work item for each new inbox conversation, linked to it as
  // `created_from`. A redelivered event finds the work item and leaves it.
  const flows = createFlows({
    flows: [conversationToWorkItem()],
    clients: (tenant) => blocks(admin.$client, tenant),
  });

  return blocks(admin.$client).outbox.relayRoute({
    secret: process.env["CRON_SECRET"],
    consumers: { rules: sink, flows: flows.sink() },
  })(request);
}
