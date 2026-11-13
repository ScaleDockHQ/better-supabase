import type { BlockOf } from "../define-block.ts";
import type { IncomingWebhooksEvents, WebhooksEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { incomingWebhooksEvents, webhooksEvents } from "./events.ts";
import { createIncomingWebhooks } from "./incoming.ts";
import { webhooksSqlOptions, incomingWebhooksSqlOptions } from "./options.ts";
import { createWebhooks } from "./outgoing.ts";

/** The `webhooks` block's manifest (ADR 0029). */
export const webhooksBlock: BlockOf<
  "webhooks",
  typeof createWebhooks,
  WebhooksEvents
> = defineBlock({
  name: "webhooks",
  sql: ["webhooks"],
  options: { webhooks: webhooksSqlOptions },
  events: webhooksEvents,
  create: createWebhooks,
  category: "developer",
  entities: {
    webhook_endpoint: {
      mutability: "editable",
      emits: { create: false, update: false, delete: false },
    },
  },
  concerns: ["lifecycle"],
  description:
    "Outgoing webhooks: endpoints subscribed to event types, a delivery log unique per endpoint and event with leases and retries, direct dispatch, secrets in Vault with overlap while rotating, auto-disable after an endpoint keeps failing and redelivery.",
  recipes: ["webhook-endpoints"],
});

/** The `incoming-webhooks` block's manifest (ADR 0029). */
export const incomingWebhooksBlock: BlockOf<
  "incoming-webhooks",
  typeof createIncomingWebhooks,
  IncomingWebhooksEvents
> = defineBlock({
  name: "incoming-webhooks",
  sql: ["incoming-webhooks"],
  options: { "incoming-webhooks": incomingWebhooksSqlOptions },
  events: incomingWebhooksEvents,
  create: createIncomingWebhooks,
  category: "developer",
  entities: {
    incoming_webhook: {
      mutability: "editable",
      emits: { create: true, update: true, delete: true },
    },
  },
  description:
    "Per-tenant trigger URLs with a hashed token, optional Standard Webhooks or HMAC verification, a body size limit, receive counters and the last status; deliveries go to the webhook inbox with the endpoint's tenant.",
});
