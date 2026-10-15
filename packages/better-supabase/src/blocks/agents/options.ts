import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.agents.options`. */
export type AgentsSqlOptions = {
  readonly maxInstructions?: number;
};

export const agentsSqlOptions: BlockOptionsSchema<AgentsSqlOptions> =
  blockOptions<AgentsSqlOptions>({
    maxInstructions: option.number({ default: 100_000 }),
  });
