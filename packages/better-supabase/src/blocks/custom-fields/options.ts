import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.custom-fields.options`. */
export type CustomFieldsSqlOptions = { readonly layout?: string };

export const customFieldsSqlOptions: BlockOptionsSchema<CustomFieldsSqlOptions> =
  blockOptions<CustomFieldsSqlOptions>({
    layout: option.string({ default: "normalized" }),
  });
