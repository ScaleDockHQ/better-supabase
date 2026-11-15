import type { BlockCall } from "../../core/block-helpers.ts";
import type { JobRef, JobSource, JobStatus } from "../../core/jobs.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { DispatchInput } from "./outgoing-types.ts";

import { dbError } from "../../core/errors.ts";
import { jobRef, jobResultOf } from "../../core/jobs.ts";
import { isRecord } from "../shared.ts";

/** What `jobs.get` returns as the `result` of a delivered webhook. */
export interface WebhookDeliveryRun {
  readonly id: string;
  readonly endpointId: string;
  readonly type: string;
  readonly status: string;
  readonly attempt: number;
  readonly responseStatus: number | null;
  readonly durationMs: number | null;
  readonly lastError: string | null;
  readonly processedAt: string | null;
  readonly createdAt: string;
}

/** The `webhook` job kind (ADR 1032): `dispatchJob` and `redeliverJob` start it. */
export interface WebhookJobs {
  /** `dispatch` that returns `{ jobId: "webhook:<delivery id>" }`. */
  dispatchJob(input: DispatchInput): AsyncResult<JobRef>;
  /** `redeliver` that returns the `{ jobId }` of the delivery queued again. */
  redeliverJob(deliveryId: string): AsyncResult<JobRef>;
  readonly jobs: JobSource;
}

const textOf = (value: unknown): string | null =>
  typeof value === "string" ? value : null;

const numberOf = (value: unknown): number | null =>
  typeof value === "number" ? value : null;

function runOf(value: unknown): WebhookDeliveryRun | null {
  if (
    !isRecord(value) ||
    typeof value["id"] !== "string" ||
    typeof value["status"] !== "string"
  ) {
    return null;
  }

  return {
    id: value["id"],
    endpointId: textOf(value["endpointId"]) ?? "",
    type: textOf(value["type"]) ?? "",
    status: value["status"],
    attempt: numberOf(value["attempt"]) ?? 0,
    responseStatus: numberOf(value["responseStatus"]),
    durationMs: numberOf(value["durationMs"]),
    lastError: textOf(value["lastError"]),
    processedAt: textOf(value["processedAt"]),
    createdAt: textOf(value["createdAt"]) ?? "",
  };
}

/**
 * A delivery's status as a job status: `pending` waits, `delivering` and
 * `retrying` are in progress, `succeeded` completed, and `dead` and `canceled`
 * failed. Undefined for a status this version does not know.
 */
function statusOf(status: string): JobStatus | undefined {
  switch (status) {
    case "pending": {
      return "pending";
    }

    case "delivering":
    case "retrying": {
      return "running";
    }

    case "succeeded": {
      return "completed";
    }

    case "dead":
    case "canceled": {
      return "failed";
    }

    default: {
      return undefined;
    }
  }
}

/**
 * The `webhook` job source over `get_webhook_delivery`, which shows only the
 * deliveries the caller may read.
 */
export function webhookJobs(db: BlockCall): WebhookJobs {
  const jobs: JobSource = {
    get: (id) =>
      db("get_webhook_delivery", { delivery: id }, runOf).map((run) => {
        const status = run === null ? undefined : statusOf(run.status);

        if (run === null || status === undefined) {
          return null;
        }

        return jobResultOf("webhook", run.id, {
          status,
          ...(status === "completed" ? { result: run } : {}),
          ...(status === "failed"
            ? {
                error: dbError(
                  "raised",
                  run.lastError ?? `The delivery was ${run.status}`,
                  {
                    hint:
                      run.status === "dead"
                        ? "WEBHOOK_DELIVERY_DEAD"
                        : "WEBHOOK_DELIVERY_CANCELED",
                  },
                ),
              }
            : {}),
        });
      }),
  };

  return {
    jobs,
    dispatchJob: (input) =>
      db(
        "dispatch_webhook",
        {
          endpoint: input.endpointId,
          event_type: input.type,
          payload: input.data ?? {},
          run_id: input.runId ?? null,
          event_id: input.eventId ?? null,
        },
        (value) => jobRef("webhook", String(value)),
      ),
    redeliverJob: (deliveryId) =>
      db("redeliver_webhook", { delivery: deliveryId }, (value) =>
        jobRef("webhook", String(value)),
      ),
  };
}
