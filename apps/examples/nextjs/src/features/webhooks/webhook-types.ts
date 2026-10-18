import * as v from "valibot";

/** `WEBHOOK_STATUSES` of the webhooks-out SQL module. */
export const WebhookStatus = v.picklist([
  "pending",
  "delivering",
  "succeeded",
  "retrying",
  "dead",
  "canceled",
]);

export type WebhookStatus = v.InferOutput<typeof WebhookStatus>;

export interface WebhookEndpointRow {
  readonly id: string;
  readonly name: string;
  readonly url: string;
  readonly enabled: boolean;
  readonly eventTypes: readonly string[];
  readonly failingSince: string | null;
  readonly disabledReason: string | null;
  readonly createdAt: string;
}

export interface WebhookDeliveryRow {
  readonly id: string;
  readonly endpointName: string;
  readonly eventType: string;
  readonly status: WebhookStatus;
  readonly attempt: number;
  readonly responseStatus: number | null;
  readonly lastError: string | null;
  readonly createdAt: string;
}

/** Event filters: the exact type, `*`, or a `prefix.*` wildcard. */
export const EVENT_PATTERN = /^(\*|[a-z0-9_-]+(\.[a-z0-9_-]+)*(\.\*)?)$/;
