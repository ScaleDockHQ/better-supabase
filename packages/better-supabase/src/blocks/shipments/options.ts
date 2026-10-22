import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.shipments.options`. */
export type ShipmentsSqlOptions = {
  /** Extra columns on the shipments table, as `extraColumns` elsewhere. */
  readonly extraColumns?: unknown;
};

export const shipmentsSqlOptions: BlockOptionsSchema<ShipmentsSqlOptions> =
  blockOptions<ShipmentsSqlOptions>({ extraColumns: option.unknown() });
