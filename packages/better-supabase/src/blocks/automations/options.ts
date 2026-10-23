import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.automations.options`. */
export type AutomationsSqlOptions = {
  /** The most conditions one rule may hold. */
  readonly maxConditions?: number;
  /** How deep groups may nest, the root group counting as 1. */
  readonly maxDepth?: number;
  /** The most actions one rule may run. */
  readonly maxActions?: number;
  /**
   * Keys of default automations the blocks ship turned off, such as
   * `quotes.quote_to_order`, to ship turned on.
   */
  readonly enable?: readonly string[];
  /** Keys of default automations to ship turned off. */
  readonly disable?: readonly string[];
};

export const automationsSqlOptions: BlockOptionsSchema<AutomationsSqlOptions> =
  blockOptions<AutomationsSqlOptions>({
    maxConditions: option.number({ default: 50 }),
    maxDepth: option.number({ default: 4 }),
    maxActions: option.number({ default: 20 }),
    enable: option.strings({ default: [] }),
    disable: option.strings({ default: [] }),
  });
