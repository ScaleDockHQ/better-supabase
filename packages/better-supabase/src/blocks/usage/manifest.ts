import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { usageSqlOptions } from "./options.ts";
import { createUsage } from "./usage.ts";

/** The `usage` block's manifest (ADR 0029). */
export const usageBlock: BlockOf<"usage", typeof createUsage> = defineBlock({
  name: "usage",
  sql: ["usage"],
  options: { usage: usageSqlOptions },
  create: createUsage,
  category: "commerce",
  entities: { usage: { mutability: "append-only", emits: { create: false } } },
  description:
    "Usage counters per tenant, meter and day with idempotent increments, quotas per tenant or plan, within_quota() for policies and consume_quota(), which raises quota_exceeded. unreported_usage() feeds reportUsageToStripe.",
  recipes: ["usage-meter"],
});
