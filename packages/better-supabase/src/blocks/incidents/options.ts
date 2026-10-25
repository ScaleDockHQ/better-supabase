import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.incidents.options`. */
export type IncidentsSqlOptions = { readonly extraColumns?: ExtraColumns };

export const incidentsSqlOptions: BlockOptionsSchema<IncidentsSqlOptions> =
  blockOptions<IncidentsSqlOptions>({ extraColumns: option.extraColumns() });
