import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.webhooks.options`. */
export type WebhooksSqlOptions = {
  readonly allowHttp?: boolean;
  readonly defaultFormat?: string;
  readonly disableAfter?: string;
  readonly eventIdType?: unknown;
  readonly partitioned?: boolean;
  readonly runIdType?: unknown;
  readonly secretStorage?: string;
  readonly statuses?: unknown;
};

export const webhooksSqlOptions: BlockOptionsSchema<WebhooksSqlOptions> =
  blockOptions<WebhooksSqlOptions>({
    allowHttp: option.boolean({ default: false, client: true }),
    defaultFormat: option.string({ default: "cloudevents", client: true }),
    disableAfter: option.string({ default: "5 days" }),
    eventIdType: option.unknown(),
    partitioned: option.boolean({ default: false }),
    runIdType: option.unknown(),
    secretStorage: option.string({ default: "vault" }),
    statuses: option.unknown(),
  });

/** `blocks.incoming-webhooks.options`. */
export type IncomingWebhooksSqlOptions = {
  readonly maxBodyBytes?: number;
  readonly secretStorage?: string;
};

export const incomingWebhooksSqlOptions: BlockOptionsSchema<IncomingWebhooksSqlOptions> =
  blockOptions<IncomingWebhooksSqlOptions>({
    maxBodyBytes: option.number({ default: 1_048_576 }),
    secretStorage: option.string({ default: "vault" }),
  });
