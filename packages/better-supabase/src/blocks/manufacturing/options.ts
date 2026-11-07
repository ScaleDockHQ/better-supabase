import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.manufacturing.options`. */
export type ManufacturingSqlOptions = {
  /** Extra columns on the production orders table, set through `fields`. */
  /**
   * What purchase suggestions create: draft purchase orders (`order`, the
   * default) or purchase requisitions that go through approval
   * (`requisition`).
   */
  readonly purchaseSuggestions?: "order" | "requisition";
};

export const manufacturingSqlOptions: BlockOptionsSchema<ManufacturingSqlOptions> =
  blockOptions<ManufacturingSqlOptions>({
    purchaseSuggestions: option.string<"order" | "requisition">({
      default: "order",
    }),
  });
