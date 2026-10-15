import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.jobs.options`. */
export type JobsSqlOptions = {
  readonly backend?: string;
  readonly scheduler?: string;
};

export const jobsSqlOptions: BlockOptionsSchema<JobsSqlOptions> =
  blockOptions<JobsSqlOptions>({
    backend: option.string({ default: "pgmq" }),
    scheduler: option.string({ default: "pg_cron" }),
  });

/** `blocks.rate-limit.options`. */
export type RateLimitSqlOptions = {
  readonly preRequest?: boolean;
};

export const rateLimitSqlOptions: BlockOptionsSchema<RateLimitSqlOptions> =
  blockOptions<RateLimitSqlOptions>({
    preRequest: option.boolean({ default: true }),
  });
