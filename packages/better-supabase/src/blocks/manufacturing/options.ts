import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.manufacturing.options`. */
export type ManufacturingSqlOptions = {
  /** Extra columns on the production orders table, set through `fields`. */
  readonly extraColumns?: ExtraColumns;
  /**
   * What purchase suggestions create: draft purchase orders (`order`, the
   * default) or purchase requisitions that go through approval
   * (`requisition`).
   */
  readonly purchaseSuggestions?: "order" | "requisition";
};

export const manufacturingSqlOptions: BlockOptionsSchema<ManufacturingSqlOptions> =
  blockOptions<ManufacturingSqlOptions>({
    extraColumns: option.extraColumns(),
    purchaseSuggestions: option.string<"order" | "requisition">({
      default: "order",
    }),
  });
