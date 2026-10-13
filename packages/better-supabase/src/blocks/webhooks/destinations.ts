import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { SqlClient } from "../../postgres/executor.ts";
import type { Jobs, QueueSchemas } from "../jobs/types.ts";
import type {
  IncomingDelivery,
  IncomingDestination,
} from "./incoming-types.ts";

import { receiveWebhook } from "../jobs/webhook-inbox.ts";

/**
 * Stores deliveries in the webhook inbox under `source` (the delivery's
 * source when unset), with the endpoint's tenant and the id
 * `<endpoint id>:<message id>`. The default destination of
 * `createIncomingWebhooks`.
 */
export function inboxDestination(
  sql: SqlClient,
  options: { readonly source?: string } = {},
): IncomingDestination {
  return {
    apiVersion: 1,
    name: "inbox",
    deliver: (delivery) =>
      receiveWebhook(sql, {
        source: options.source ?? delivery.source,
        id: `${delivery.endpoint.id}:${delivery.messageId}`,
        type: delivery.type,
        payload: delivery.payload,
        headers: delivery.headers,
        tenant: delivery.endpoint.tenant,
      }),
  };
}

export interface JobsDestinationOptions<
  Q extends QueueSchemas,
  N extends Extract<keyof Q, string>,
> {
  readonly queue: N;
  /**
   * The job payload for a delivery, checked by the queue's schema. Unset, the
   * queue receives the delivery itself.
   */
  readonly payload?: (
    delivery: IncomingDelivery,
  ) => StandardSchemaV1.InferInput<Q[N]>;
  /** Defaults to the queue's default (5). */
  readonly maxAttempts?: number;
}

/**
 * Enqueues each delivery once on a jobs queue (`jobs.enqueueOnce`) with the
 * dedupe key `<endpoint id>:<message id>` and the endpoint's tenant as the
 * job's tenant. A repeat is a duplicate while the job waits, runs or stays
 * archived; `jobs.purge` ends that window.
 */
export function jobsDestination<
  Q extends QueueSchemas,
  N extends Extract<keyof Q, string>,
>(jobs: Jobs<Q>, options: JobsDestinationOptions<Q, N>): IncomingDestination {
  return {
    apiVersion: 1,
    name: "jobs",
    deliver: (delivery) =>
      jobs
        .enqueueOnce(
          options.queue,
          // SAFETY: without a mapper the queue's schema validates the delivery itself.
          options.payload?.(delivery) ??
            (delivery as StandardSchemaV1.InferInput<Q[N]>),
          {
            dedupeKey: `${delivery.endpoint.id}:${delivery.messageId}`,
            context: { tenant: delivery.endpoint.tenant },
            ...(options.maxAttempts === undefined
              ? {}
              : { maxAttempts: options.maxAttempts }),
          },
        )
        .orThrow(),
  };
}
