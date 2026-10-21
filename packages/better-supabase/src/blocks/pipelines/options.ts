import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.pipelines.options`. */
export type PipelinesSqlOptions = {
  readonly subjects?: unknown;
  readonly extraColumns?: unknown;
};

export const pipelinesSqlOptions: BlockOptionsSchema<PipelinesSqlOptions> =
  blockOptions<PipelinesSqlOptions>({
    subjects: option.unknown(),
    extraColumns: option.unknown(),
  });
