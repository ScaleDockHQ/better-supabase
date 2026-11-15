import type { JobSource, JobStatus } from "../../core/jobs.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { QueueRun, QueueRunState } from "./backends.ts";

import { dbError } from "../../core/errors.ts";
import { jobResultOf } from "../../core/jobs.ts";
import { AsyncResult as Async } from "../../core/result.ts";

/** The id after the `queue:` kind is `<queue name>:<message id>`. */
function parseRunId(
  id: string,
): { readonly queue: string; readonly id: number } | undefined {
  const at = id.indexOf(":");
  const message = Number(id.slice(at + 1));

  return at <= 0 || !Number.isSafeInteger(message)
    ? undefined
    : { queue: id.slice(0, at), id: message };
}

/**
 * A message that waits (or waits out a retry backoff) is `pending`, one a
 * worker holds is `running`, an archived one is `completed`, and a dead letter
 * is `failed`.
 */
function statusOf(state: QueueRunState): JobStatus {
  switch (state) {
    case "waiting": {
      return "pending";
    }

    case "running": {
      return "running";
    }

    case "done": {
      return "completed";
    }

    case "dead": {
      return "failed";
    }

    default: {
      const unreachable: never = state;

      return unreachable;
    }
  }
}

/**
 * The `queue` job source (ADR 1076): `jobs.get("queue:<queue>:<id>")` reads the
 * run record of a message that `enqueueJob` or any block that enqueues
 * returned. A queue this client does not declare reads as unknown.
 */
export function queueRuns(options: {
  readonly get: (queue: string, id: number) => AsyncResult<QueueRun | null>;
  readonly declared: (queue: string) => boolean;
}): JobSource {
  return {
    get: (jobId) => {
      const parsed = parseRunId(jobId);

      if (parsed === undefined || !options.declared(parsed.queue)) {
        return Async.ok(null);
      }

      return options.get(parsed.queue, parsed.id).map((run) => {
        if (run === null) {
          return null;
        }

        const status = statusOf(run.state);

        return jobResultOf("queue", `${run.queue}:${String(run.id)}`, {
          status,
          ...(status === "completed" ? { result: run } : {}),
          ...(status === "failed"
            ? {
                error: dbError(
                  "raised",
                  run.lastError ?? "The job ran out of attempts",
                  { hint: "QUEUE_JOB_DEAD" },
                ),
              }
            : {}),
        });
      });
    },
  };
}
