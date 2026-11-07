import type { BlockOf } from "../define-block.ts";

import { createRateLimit } from "../../rate-limit/rate-limit.ts";
import { defineBlock } from "../define-block.ts";
import { CRON_SECRET_ENV, DATABASE_URL_ENV } from "../wiring.ts";
import { createIdempotency } from "./idempotency.ts";
import { queueSqlOptions, rateLimitSqlOptions } from "./options.ts";
import { createQueue } from "./queue.ts";
import { createWebhookInbox } from "./webhook-inbox.ts";

/** The `queue` block's manifest (ADR 0029). */
export const queueBlock: BlockOf<"queue", typeof createQueue> = defineBlock({
  name: "queue",
  sql: ["queue", "housekeeping"],
  options: { queue: queueSqlOptions },
  create: createQueue,
  category: "automation",
  description:
    "Typed jobs on Supabase Queues (pgmq) or a plain table (blocks.queue.options.backend): leases, retries with backoff, dead letters, deduplication keys, queue stats, and schedules with pg_cron or the drain route.",
  env: [CRON_SECRET_ENV, { ...DATABASE_URL_ENV, required: false }],
  routes: ["jobs-drain"],
  workers: [
    {
      name: "queue-drain",
      description:
        "Enqueues due schedules and block timers, then runs the queued jobs.",
      path: "/api/jobs/drain",
      schedule: "* * * * *",
    },
  ],
  recipes: ["job-runs-table"],
});

/** The `idempotency` block's manifest (ADR 0029). */
export const idempotencyBlock: BlockOf<
  "idempotency",
  typeof createIdempotency
> = defineBlock({
  name: "idempotency",
  sql: ["idempotency"],
  create: createIdempotency,
  category: "automation",
  description:
    "Stores responses by Idempotency-Key so retried requests replay the first result instead of running twice.",
});

/** The `rate-limit` block's manifest (ADR 0029). */
export const rateLimitBlock: BlockOf<"rate-limit", typeof createRateLimit> =
  defineBlock({
    name: "rate-limit",
    sql: ["rate-limit"],
    options: { "rate-limit": rateLimitSqlOptions },
    create: createRateLimit,
    category: "automation",
    description:
      "Fixed-window limits on Data API writes (POST, PATCH, PUT, DELETE) per user or claim, checked by pgrst.db_pre_request. Over the limit: 429 with Retry-After.",
  });

/** The `webhook-inbox` block's manifest (ADR 0029). */
export const webhookInboxBlock: BlockOf<
  "webhook-inbox",
  typeof createWebhookInbox
> = defineBlock({
  name: "webhook-inbox",
  sql: ["webhook-inbox"],
  create: createWebhookInbox,
  category: "automation",
  description:
    "Stores verified webhooks once per message id, per tenant when given, then processes them with leases, retries and checkpoints, in its own table or one of the app's.",
});
