import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.webhooks-out.options`. */
export type WebhooksOutSqlOptions = {
  readonly allowHttp?: boolean;
  readonly defaultFormat?: string;
  readonly disableAfter?: string;
  readonly eventIdType?: unknown;
  readonly partitioned?: boolean;
  readonly runIdType?: unknown;
  readonly secretStorage?: string;
  readonly statuses?: unknown;
};

export const webhooksOutSqlOptions: BlockOptionsSchema<WebhooksOutSqlOptions> =
  blockOptions<WebhooksOutSqlOptions>({
    allowHttp: option.boolean({ default: false, client: true }),
    defaultFormat: option.string({ default: "cloudevents", client: true }),
    disableAfter: option.string({ default: "5 days" }),
    eventIdType: option.unknown(),
    partitioned: option.boolean({ default: false }),
    runIdType: option.unknown(),
    secretStorage: option.string({ default: "vault" }),
    statuses: option.unknown(),
  });

/** `blocks.webhooks-in.options`. */
export type WebhooksInSqlOptions = {
  readonly maxBodyBytes?: number;
  readonly secretStorage?: string;
  readonly subjects?: unknown;
};

export const webhooksInSqlOptions: BlockOptionsSchema<WebhooksInSqlOptions> =
  blockOptions<WebhooksInSqlOptions>({
    maxBodyBytes: option.number({ default: 1_048_576 }),
    secretStorage: option.string({ default: "vault" }),
    subjects: option.unknown(),
  });
