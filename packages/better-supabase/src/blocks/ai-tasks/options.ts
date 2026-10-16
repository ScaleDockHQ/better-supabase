import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.ai-tasks.options`. */
export type AiTasksSqlOptions = {
  readonly queue?: string;
  readonly staleAfter?: string;
  readonly maxPrompt?: number;
  readonly extraColumns?: unknown;
};

export const aiTasksSqlOptions: BlockOptionsSchema<AiTasksSqlOptions> =
  blockOptions<AiTasksSqlOptions>({
    queue: option.string({ default: "ai_task_run" }),
    staleAfter: option.string({ default: "30 minutes" }),
    maxPrompt: option.number({ default: 20000 }),
    extraColumns: option.unknown(),
  });
