import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { CRON_SECRET_ENV } from "../wiring.ts";
import { outboxSqlOptions } from "./options.ts";
import { createOutbox } from "./outbox.ts";

/**
 * The `outbox` block's manifest (ADR 0029). Set the CloudEvents source with
 * `outboxBlock.with({ source: "https://app.example.com" })`.
 */
export const outboxBlock: BlockOf<"outbox", typeof createOutbox> = defineBlock({
  name: "outbox",
  sql: ["outbox"],
  options: { outbox: outboxSqlOptions },
  create: createOutbox,
  category: "automation",
  env: [
    CRON_SECRET_ENV,
    {
      key: "APP_URL",
      description:
        "The app's public URL, the CloudEvents source of the events the outbox sends.",
      required: false,
    },
  ],
  routes: ["outbox-relay"],
  workers: [
    {
      name: "outbox-relay",
      description:
        "Delivers outbox events to their consumers and runs the automations they trigger.",
      path: "/api/outbox",
      schedule: "* * * * *",
    },
  ],
});
