import type { BlockOf } from "../define-block.ts";
import type { IncomingWebhooksEvents, WebhooksEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { incomingWebhooksEvents, webhooksEvents } from "./events.ts";
import { createIncomingWebhooks } from "./incoming.ts";
import { createWebhooks } from "./outgoing.ts";

/** The `webhooks` block's manifest (ADR 0029). */
export const webhooksBlock: BlockOf<
  "webhooks",
  typeof createWebhooks,
  WebhooksEvents
> = defineBlock({
  name: "webhooks",
  sql: ["webhooks-out"],
  options: {
    "webhooks-out": optionKeys([
      "allowHttp",
      "disableAfter",
      "eventIdType",
      "runIdType",
      "secretStorage",
      "statuses",
    ]),
  },
  events: webhooksEvents,
  create: createWebhooks,
  category: "platform",
});

/** The `incoming-webhooks` block's manifest (ADR 0029). */
export const incomingWebhooksBlock: BlockOf<
  "incoming-webhooks",
  typeof createIncomingWebhooks,
  IncomingWebhooksEvents
> = defineBlock({
  name: "incoming-webhooks",
  sql: ["webhooks-in"],
  options: {
    "webhooks-in": optionKeys(["maxBodyBytes", "secretStorage", "subjects"]),
  },
  events: incomingWebhooksEvents,
  create: createIncomingWebhooks,
  category: "platform",
});
