import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.connectors.options`. */
export type ConnectorsSqlOptions = {
  readonly allowHttp?: boolean;
  readonly trustFirstUse?: boolean;
  readonly sessionTtl?: string;
  readonly extraColumns?: unknown;
};

export const connectorsSqlOptions: BlockOptionsSchema<ConnectorsSqlOptions> =
  blockOptions<ConnectorsSqlOptions>({
    allowHttp: option.boolean({ default: false }),
    trustFirstUse: option.boolean({ default: true }),
    sessionTtl: option.string({ default: "1 hour" }),
    extraColumns: option.unknown(),
  });
