import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.state-machine.options`. */
export type StateMachineSqlOptions = { readonly machines?: unknown };

export const stateMachineSqlOptions: BlockOptionsSchema<StateMachineSqlOptions> =
  blockOptions<StateMachineSqlOptions>({ machines: option.unknown() });
