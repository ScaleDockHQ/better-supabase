import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.pipelines.options`. */
export type PipelinesSqlOptions = {
  readonly subjects?: unknown;
};

export const pipelinesSqlOptions: BlockOptionsSchema<PipelinesSqlOptions> =
  blockOptions<PipelinesSqlOptions>({
    subjects: option.unknown(),
  });
