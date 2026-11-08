import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.pipelines.options`. */
export type PipelinesSqlOptions = {
  /**
   * The table and column that hold an organization's brand; a binding's
   * `brands` then starts an organization of that brand with its own stages.
   */
  readonly brand?: {
    readonly table: string;
    readonly column: string;
    readonly tenant?: string;
  };
};

export const pipelinesSqlOptions: BlockOptionsSchema<PipelinesSqlOptions> =
  blockOptions<PipelinesSqlOptions>({ brand: option.unknown() });
