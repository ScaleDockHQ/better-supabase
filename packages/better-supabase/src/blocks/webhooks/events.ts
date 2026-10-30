import type {
  IncomingWebhookEventData,
  WebhookEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `webhooks` block: type to data. */
export type WebhooksEvents = {
  readonly "webhook_endpoint.delivered": WebhookEventData;
  readonly "webhook_endpoint.failed": WebhookEventData;
  readonly "webhook_endpoint.disabled": WebhookEventData;
  readonly "webhook_endpoint.secret_rotated": WebhookEventData;
};

/** The `webhooks` block's event types, for its manifest and `onBlockEvent`. */
export const webhooksEvents: Events<WebhooksEvents> = defineEvents({
  "webhook_endpoint.delivered": event<WebhookEventData>(),
  "webhook_endpoint.failed": event<WebhookEventData>(),
  "webhook_endpoint.disabled": event<WebhookEventData>(),
  "webhook_endpoint.secret_rotated": event<WebhookEventData>(),
});

/** The events of the `incoming-webhooks` block: type to data. */
export type IncomingWebhooksEvents = {
  readonly "incoming_webhook.created": IncomingWebhookEventData;
  readonly "incoming_webhook.updated": IncomingWebhookEventData;
  readonly "incoming_webhook.enabled_changed": IncomingWebhookEventData;
  readonly "incoming_webhook.token_rotated": IncomingWebhookEventData;
  readonly "incoming_webhook.secret_rotated": IncomingWebhookEventData;
  readonly "incoming_webhook.deleted": IncomingWebhookEventData;
};

/**
 * The `incoming-webhooks` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const incomingWebhooksEvents: Events<IncomingWebhooksEvents> =
  defineEvents({
    "incoming_webhook.created": event<IncomingWebhookEventData>(),
    "incoming_webhook.updated": event<IncomingWebhookEventData>(),
    "incoming_webhook.enabled_changed": event<IncomingWebhookEventData>(),
    "incoming_webhook.token_rotated": event<IncomingWebhookEventData>(),
    "incoming_webhook.secret_rotated": event<IncomingWebhookEventData>(),
    "incoming_webhook.deleted": event<IncomingWebhookEventData>(),
  });
