import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.queue.options`. */
export type QueueSqlOptions = {
  readonly backend?: string;
  readonly scheduler?: string;
  readonly httpTick?: boolean;
};

export const queueSqlOptions: BlockOptionsSchema<QueueSqlOptions> =
  blockOptions<QueueSqlOptions>({
    backend: option.string({ default: "pgmq" }),
    scheduler: option.string({ default: "pg_cron" }),
    httpTick: option.boolean({ default: false }),
  });

/** `blocks.rate-limit.options`. */
export type RateLimitSqlOptions = { readonly preRequest?: boolean };

export const rateLimitSqlOptions: BlockOptionsSchema<RateLimitSqlOptions> =
  blockOptions<RateLimitSqlOptions>({
    preRequest: option.boolean({ default: true }),
  });
