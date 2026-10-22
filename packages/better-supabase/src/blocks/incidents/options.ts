import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.incidents.options`. */
export type IncidentsSqlOptions = {
  readonly extraColumns?: unknown;
};

export const incidentsSqlOptions: BlockOptionsSchema<IncidentsSqlOptions> =
  blockOptions<IncidentsSqlOptions>({
    extraColumns: option.unknown(),
  });
