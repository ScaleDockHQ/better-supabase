import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createIdempotency } from "./idempotency.ts";
import {
  jobsSqlOptions,
  rateLimitSqlOptions,
  webhookInboxSqlOptions,
} from "./options.ts";
import { createJobs } from "./queue.ts";
import { createRateLimit } from "./rate-limit.ts";
import { createWebhookInbox } from "./webhook-inbox.ts";

/** The `jobs` block's manifest (ADR 0029). */
export const jobsBlock: BlockOf<"jobs", typeof createJobs> = defineBlock({
  name: "jobs",
  sql: ["jobs"],
  options: {
    jobs: jobsSqlOptions,
  },
  create: createJobs,
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
    options: {
      "rate-limit": rateLimitSqlOptions,
    },
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
  options: {
    "webhook-inbox": webhookInboxSqlOptions,
  },
  create: createWebhookInbox,
  category: "developer",
});
