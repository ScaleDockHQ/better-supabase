import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.observations.options`. */
export type ObservationsSqlOptions = {
  /**
   * The system definitions to install: `none` (default) or `vitals`, the vital
   * signs with their LOINC codes and UCUM units.
   */
  readonly defaults?: "none" | "vitals";
  /**
   * Partitions the observations table by month of `created_at`. Amendments then
   * keep their link without a foreign key, and the function checks the ingest
   * key instead of a unique index. Default `false`.
   */
  readonly partitioned?: boolean;
  /** Extra columns on the observations table. */
  readonly extraColumns?: ExtraColumns;
};

export const observationsSqlOptions: BlockOptionsSchema<ObservationsSqlOptions> =
  blockOptions<ObservationsSqlOptions>({
    defaults: option.string<"none" | "vitals">({ default: "none" }),
    partitioned: option.boolean({ default: false }),
    extraColumns: option.extraColumns(),
  });
