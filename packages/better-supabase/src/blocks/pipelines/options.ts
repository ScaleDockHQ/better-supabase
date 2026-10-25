import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.pipelines.options`. */
export type PipelinesSqlOptions = { readonly extraColumns?: ExtraColumns };

export const pipelinesSqlOptions: BlockOptionsSchema<PipelinesSqlOptions> =
  blockOptions<PipelinesSqlOptions>({ extraColumns: option.extraColumns() });
