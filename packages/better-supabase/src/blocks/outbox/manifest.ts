import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { outboxSqlOptions } from "./options.ts";
import { createOutbox } from "./outbox.ts";

/**
 * The `outbox` block's manifest (ADR 0029). Set the CloudEvents source with
 * `outboxBlock.with({ source: "https://app.example.com" })`.
 */
export const outboxBlock: BlockOf<"outbox", typeof createOutbox> = defineBlock({
  name: "outbox",
  sql: ["outbox"],
  options: {
    outbox: outboxSqlOptions,
  },
  create: createOutbox,
  category: "platform",
});
