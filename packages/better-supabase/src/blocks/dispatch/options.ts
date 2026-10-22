import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.dispatch.options`. */
export type DispatchSqlOptions = {
  /** Extra columns on the work orders table, as `extraColumns` elsewhere. */
  readonly extraColumns?: unknown;
  /** The IANA zone a work order's `day` and the board's days are in. */
  readonly timeZone?: string;
  /** A slot's length when only its start is given, as a Postgres interval. */
  readonly defaultDuration?: string;
};

export const dispatchSqlOptions: BlockOptionsSchema<DispatchSqlOptions> =
  blockOptions<DispatchSqlOptions>({
    extraColumns: option.unknown(),
    timeZone: option.string({ default: "UTC", client: true }),
    defaultDuration: option.string({ default: "1 hour" }),
  });
