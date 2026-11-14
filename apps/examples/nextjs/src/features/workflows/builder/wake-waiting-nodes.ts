import type { WorkflowRun } from "better-supabase/blocks/workflows";

import { nodeWaitToken } from "better-supabase/blocks/workflow-editor";
import { approvalWaiter } from "better-supabase/workflow-sdk";
import * as v from "valibot";
import { HookNotFoundError } from "workflow/errors";

const FINISHED_EVENTS = [
  "workflow_run.completed",
  "workflow_run.failed",
  "workflow_run.cancelled",
] as const;

/** The part of an outbox event the wake reads. */
interface RunEvent {
  readonly type: string;
  readonly payload: unknown;
}

const SUB_PREFIX = "sub:";

const isFinished = (type: string): boolean =>
  FINISHED_EVENTS.some((known) => known === type);

const RunPayload = v.object({
  runId: v.optional(v.string()),
  status: v.optional(v.string()),
  error: v.optional(v.nullable(v.string())),
});

/**
 * Resumes the parent node of a finished child run. A `sub-workflow` node keys
 * its child `sub:<parent key>:<node>`, so the parent's wait token is the
 * child's key without the prefix. Pass every `workflow_run.*` outbox event;
 * other events and runs that no node waits on are ignored. Returns whether a
 * parent was woken.
 */
export async function wakeParentOfRun(
  event: RunEvent,
  runs: {
    get(
      run: string,
    ): PromiseLike<{
      readonly ok: boolean;
      readonly data?: Pick<WorkflowRun, "idempotencyKey"> | null | undefined;
    }>;
  },
): Promise<boolean> {
  const payload = v.safeParse(RunPayload, event.payload);
  const runId = payload.success ? payload.output.runId : undefined;

  if (!payload.success || !isFinished(event.type) || runId === undefined) {
    return false;
  }

  const found = await runs.get(runId);
  const key = found.ok ? found.data?.idempotencyKey : undefined;

  if (key === undefined || !key.startsWith(SUB_PREFIX)) {
    return false;
  }

  const [parentKey, node] = splitKey(key.slice(SUB_PREFIX.length));

  try {
    await approvalWaiter.wake(nodeWaitToken(parentKey, node), {
      status: payload.output.status ?? event.type.slice(13),
      error: payload.output.error ?? null,
    });
  } catch (cause) {
    if (!HookNotFoundError.is(cause)) {
      throw cause;
    }

    return false;
  }

  return true;
}

/**
 * `<parent key>:<node>` as the pair `nodeWaitToken` takes: the node id has no
 * colon.
 */
function splitKey(value: string): [string, string] {
  const at = value.lastIndexOf(":");

  return [value.slice(0, at), value.slice(at + 1)];
}

/** Resumes a human task's node: its run key and node id name the hook. */
export async function wakeHumanTask(
  runKey: string,
  node: string,
  completedBy: string,
): Promise<void> {
  await approvalWaiter.wake(nodeWaitToken(runKey, node), { completedBy });
}
