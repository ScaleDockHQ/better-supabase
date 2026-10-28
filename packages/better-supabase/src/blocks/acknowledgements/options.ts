import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.acknowledgements.options`. */
export interface AcknowledgementsSqlOptions extends Readonly<
  Record<string, unknown>
> {
  /**
   * Per record type, the column on the record's table that holds the current
   * version id. Without it, the current version is the newest frozen version
   * in `versions`.
   */
  readonly extraColumns?: ExtraColumns;
  readonly on?: Readonly<Record<string, { readonly versionColumn?: string }>>;
}

export const acknowledgementsSqlOptions: BlockOptionsSchema<AcknowledgementsSqlOptions> =
  blockOptions<AcknowledgementsSqlOptions>({ extraColumns: option.extraColumns(), on: option.unknown() });
