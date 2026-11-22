import type {
  QueueOptions,
  QueuePayload,
  ValidQueueName,
} from "@workflow/world";
import type { Pool } from "pg";

import { orchestratorRunIdOf } from "@workflow/world";

import type { Logger } from "../../core/logger.ts";
import type { StoredMessage } from "./types.ts";

/**
 * Clears the run's owed wake-up (`workflow_runs.wake_pending`) once an
 * orchestrator delivery of it completed, as world-postgres does after its own
 * deliveries. A flag left set costs the run one extra wake-up from the sweep.
 */
export async function clearOwedWake(
  pool: Pick<Pool, "query">,
  prefix: string,
  message: StoredMessage,
): Promise<void> {
  if (!message.queueName.startsWith(prefix)) {
    return;
  }

  let runId: string | undefined;

  try {
    runId = orchestratorRunIdOf(
      JSON.parse(Buffer.from(message.body, "base64").toString("utf-8")),
    );
  } catch {
    return;
  }

  if (runId === undefined) {
    return;
  }

  await pool
    .query(
      "update workflow.workflow_runs set wake_pending = false where id = $1 and wake_pending is true",
      [runId],
    )
    .catch(() => undefined);
}

export interface SweepContext {
  readonly pool: Pick<Pool, "query">;
  readonly queue: (
    name: ValidQueueName,
    message: QueuePayload,
    opts?: QueueOptions,
  ) => Promise<unknown>;
  readonly logger: Logger;
  /** Seconds a wake-up may stay owed before it is sent again. */
  readonly recoverAfter: number;
  /** The orchestrator queue prefix, namespace included. */
  readonly prefix: string;
}

/**
 * Sends again the wake-ups runs are still owed: a running run whose
 * `wake_pending` flag stayed set for `recoverAfter` seconds lost the delivery
 * that would have cleared it (a crashed function, a dead-lettered message). One
 * message per run per window; a duplicate wake-up is a replay the runtime
 * treats as a no-op. Resolves with how many runs it woke.
 */
export async function sweepOwedWakes(context: SweepContext): Promise<number> {
  const { pool, queue, logger, recoverAfter, prefix } = context;

  const result = await pool.query<{
    id: string;
    name: string;
    spec_version: string | null;
  }>(
    `select id, name, spec_version from workflow.workflow_runs
     where status = 'running' and wake_pending
       and updated_at < now() - make_interval(secs => $1)
     order by updated_at
     limit 100`,
    [recoverAfter],
  );

  const window = Math.floor(Date.now() / (recoverAfter * 1000));
  let woken = 0;

  for (const row of result.rows) {
    const spec = Number(row.spec_version);

    try {
      await queue(
        // SAFETY: a queue name is the validated prefix plus the run's workflow name.
        `${prefix}${row.name}`,
        {
          runId: row.id,
          ...(Number.isInteger(spec) ? { runSpecVersion: spec } : {}),
        },
        { idempotencyKey: `wake:${row.id}:${String(window)}` },
      );
      woken += 1;
    } catch (cause) {
      logger.warn("A workflow wake-up could not be sent again", {
        runId: row.id,
        error: cause,
      });
    }
  }

  return woken;
}
