import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createIdempotency } from "./idempotency.ts";
import {
  queueSqlOptions,
  rateLimitSqlOptions,
  webhookInboxSqlOptions,
} from "./options.ts";
import { createQueue } from "./queue.ts";
import { createRateLimit } from "./rate-limit.ts";
import { createWebhookInbox } from "./webhook-inbox.ts";

/** The `jobs` block's manifest (ADR 0029). */
export const queueBlock: BlockOf<"queue", typeof createQueue> = defineBlock({
  name: "queue",
  sql: ["queue"],
  options: { queue: queueSqlOptions },
  create: createQueue,
  category: "automation",
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
  category: "developer",
});

/** The `rate-limit` block's manifest (ADR 0029). */
export const rateLimitBlock: BlockOf<"rate-limit", typeof createRateLimit> =
  defineBlock({
    name: "rate-limit",
    sql: ["rate-limit"],
    options: { "rate-limit": rateLimitSqlOptions },
    create: createRateLimit,
    category: "developer",
  });

/** The `webhook-inbox` block's manifest (ADR 0029). */
export const webhookInboxBlock: BlockOf<
  "webhook-inbox",
  typeof createWebhookInbox
> = defineBlock({
  name: "webhook-inbox",
  sql: ["webhook-inbox"],
  options: { "webhook-inbox": webhookInboxSqlOptions },
  create: createWebhookInbox,
  category: "developer",
});
