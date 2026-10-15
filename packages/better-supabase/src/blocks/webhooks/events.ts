import type {
  IncomingWebhookEventData,
  WebhookEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `webhooks` block: type to data. */
export type WebhooksEvents = {
  readonly "webhook.delivered": WebhookEventData;
  readonly "webhook.failed": WebhookEventData;
  readonly "webhook.disabled": WebhookEventData;
  readonly "webhook.secret_rotated": WebhookEventData;
};

/** The `webhooks` block's event types, for its manifest and `onBlockEvent`. */
export const webhooksEvents: Events<WebhooksEvents> = defineEvents({
  "webhook.delivered": event<WebhookEventData>(),
  "webhook.failed": event<WebhookEventData>(),
  "webhook.disabled": event<WebhookEventData>(),
  "webhook.secret_rotated": event<WebhookEventData>(),
});

/** The events of the `incoming-webhooks` block: type to data. */
export type IncomingWebhooksEvents = {
  readonly "incoming_webhook.created": IncomingWebhookEventData;
  readonly "incoming_webhook.updated": IncomingWebhookEventData;
  readonly "incoming_webhook.enabled_set": IncomingWebhookEventData;
  readonly "incoming_webhook.token_rotated": IncomingWebhookEventData;
  readonly "incoming_webhook.secret_rotated": IncomingWebhookEventData;
  readonly "incoming_webhook.deleted": IncomingWebhookEventData;
};

/** The `incoming-webhooks` block's event types, for its manifest and `onBlockEvent`. */
export const incomingWebhooksEvents: Events<IncomingWebhooksEvents> =
  defineEvents({
    "incoming_webhook.created": event<IncomingWebhookEventData>(),
    "incoming_webhook.updated": event<IncomingWebhookEventData>(),
    "incoming_webhook.enabled_set": event<IncomingWebhookEventData>(),
    "incoming_webhook.token_rotated": event<IncomingWebhookEventData>(),
    "incoming_webhook.secret_rotated": event<IncomingWebhookEventData>(),
    "incoming_webhook.deleted": event<IncomingWebhookEventData>(),
  });
