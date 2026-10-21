import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.outbox.options`. */
export type OutboxSqlOptions = {
  readonly defaultSource?: string;
  readonly emitRoles?: readonly string[];
  readonly blockSource?: unknown;
  readonly partitioned?: boolean;
  readonly retention?: string;
  readonly settle?: string;
};

export const outboxSqlOptions: BlockOptionsSchema<OutboxSqlOptions> =
  blockOptions<OutboxSqlOptions>({
    defaultSource: option.string({ default: "" }),
    emitRoles: option.strings({ default: ["service_role"] }),
    blockSource: option.unknown(),
    partitioned: option.boolean({ default: false }),
    retention: option.string({ default: "30 days" }),
    settle: option.string({ default: "5 seconds" }),
  });
