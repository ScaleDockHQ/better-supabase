import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.templates.options`. */
export type TemplatesSqlOptions = {
  readonly extraColumns?: unknown;
};

export const templatesSqlOptions: BlockOptionsSchema<TemplatesSqlOptions> =
  blockOptions<TemplatesSqlOptions>({
    extraColumns: option.unknown(),
  });
