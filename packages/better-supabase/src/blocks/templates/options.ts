import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.templates.options`. */
export type TemplatesSqlOptions = { readonly extraColumns?: ExtraColumns };

export const templatesSqlOptions: BlockOptionsSchema<TemplatesSqlOptions> =
  blockOptions<TemplatesSqlOptions>({ extraColumns: option.extraColumns() });
