import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.rules.options`. */
export type RulesSqlOptions = {
  /** The most conditions one rule may hold. */
  readonly maxConditions?: number;
  /** How deep groups may nest, the root group counting as 1. */
  readonly maxDepth?: number;
  /** The most actions one rule may run. */
  readonly maxActions?: number;
};

export const rulesSqlOptions: BlockOptionsSchema<RulesSqlOptions> =
  blockOptions<RulesSqlOptions>({
    maxConditions: option.number({ default: 50 }),
    maxDepth: option.number({ default: 4 }),
    maxActions: option.number({ default: 20 }),
  });
