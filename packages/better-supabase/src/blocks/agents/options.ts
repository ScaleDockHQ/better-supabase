import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.agents.options`. */
export type AgentsSqlOptions = {
  readonly maxInstructions?: number;
  readonly extraColumns?: ExtraColumns;
};

export const agentsSqlOptions: BlockOptionsSchema<AgentsSqlOptions> =
  blockOptions<AgentsSqlOptions>({
    maxInstructions: option.number({ default: 100_000 }),
    extraColumns: option.extraColumns(),
  });
