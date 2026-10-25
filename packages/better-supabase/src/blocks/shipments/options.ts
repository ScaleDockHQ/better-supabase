import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.shipments.options`. */
export type ShipmentsSqlOptions = {
  /** Extra columns on the shipments table, as `extraColumns` elsewhere. */
  readonly extraColumns?: ExtraColumns;
};

export const shipmentsSqlOptions: BlockOptionsSchema<ShipmentsSqlOptions> =
  blockOptions<ShipmentsSqlOptions>({ extraColumns: option.extraColumns() });
