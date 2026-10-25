import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.queue.options`. */
export type QueueSqlOptions = {
  readonly backend?: string;
  readonly scheduler?: string;
};

export const queueSqlOptions: BlockOptionsSchema<QueueSqlOptions> =
  blockOptions<QueueSqlOptions>({
    backend: option.string({ default: "pgmq" }),
    scheduler: option.string({ default: "pg_cron" }),
  });

/** `blocks.rate-limit.options`. */
export type RateLimitSqlOptions = { readonly preRequest?: boolean };

export const rateLimitSqlOptions: BlockOptionsSchema<RateLimitSqlOptions> =
  blockOptions<RateLimitSqlOptions>({
    preRequest: option.boolean({ default: true }),
  });

/** `blocks.webhook-inbox.options`. */
export type WebhookInboxSqlOptions = { readonly extraColumns?: ExtraColumns };

export const webhookInboxSqlOptions: BlockOptionsSchema<WebhookInboxSqlOptions> =
  blockOptions<WebhookInboxSqlOptions>({ extraColumns: option.extraColumns() });
