import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.hiring.options`. */
export type HiringSqlOptions = {
  readonly candidate?: string;
  readonly extraColumns?: unknown;
};

export const hiringSqlOptions: BlockOptionsSchema<HiringSqlOptions> =
  blockOptions<HiringSqlOptions>({
    candidate: option.string({ default: "person" }),
    extraColumns: option.unknown(),
  });
