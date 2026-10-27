import type { RuleFieldSetter } from "better-supabase/blocks/automations";

import { dbError, err } from "better-supabase";
import {
  createActionRegistry,
  createRuleDispatcher,
  createRuleSink,
  createAutomationsAdmin,
  eventTarget,
  rpcTransport,
  setFieldAction,
} from "better-supabase/blocks/automations";
import { taskFromConversationAction } from "better-supabase/blocks/tasks";
import { wakeOnApproval } from "better-supabase/workflow-sdk";
import { connection } from "next/server";
import * as v from "valibot";

import { env } from "@/env";
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
 * events the `tasks` app table writes to the outbox, and the automations the
 * blocks ship on their own events, such as the inbox's "Open a task for each
 * new conversation". The `approvals` consumer resumes the graph runs waiting on
 * a decided request. Call it every minute from a cron (Vercel Cron sends
 * `Authorization: Bearer $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  // Without a request-time API, Next.js runs this handler at build time.
  await connection();
  const admin = bsb.admin();
  const schema = blockConfig.automations.api;

  // The inbox's default automation runs `tasks.from_conversation`: a work
  // item linked `created_from` the conversation, once per conversation.
  const actions = createActionRegistry([
    setFieldAction(setTaskField),
    taskFromConversationAction({
      clients: (tenant) => {
        const scoped = admin.$with({ tenant });

        return {
          inbox: scoped.inbox,
          relations: scoped.relations,
          tasks: scoped.$blocks.tasks,
        };
      },
    }),
  ]);

  const sink = createRuleSink({
    rules: createAutomationsAdmin({
      transport: rpcTransport(admin.$client, { schema }),
      schema,
    }),
    dispatcher: createRuleDispatcher({ actions }),
    load: async (event) => {
      const payload = v.safeParse(TaskEventPayload, event.payload);

      if (!event.type.startsWith("task.") || !payload.success) {
        return eventTarget(event);
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

  return admin.outbox.relayRoute({
    secret: env.CRON_SECRET,
    consumers: {
      rules: sink,
      approvals: async (events) => {
        for (const event of events) {
          await wakeOnApproval(event);
        }
      },
    },
  })(request);
}
