import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks["ai-schedules"].options`. */
export type AiSchedulesSqlOptions = {
  readonly queue?: string;
  readonly staleAfter?: string;
  readonly maxPrompt?: number;
  readonly extraColumns?: unknown;
};

export const aiSchedulesSqlOptions: BlockOptionsSchema<AiSchedulesSqlOptions> =
  blockOptions<AiSchedulesSqlOptions>({
    queue: option.string({ default: "ai_task_run" }),
    staleAfter: option.string({ default: "30 minutes" }),
    maxPrompt: option.number({ default: 20_000 }),
    extraColumns: option.unknown(),
  });
