import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.api-keys.options`. */
export type ApiKeysSqlOptions = {
  readonly scopes?: "catalog" | readonly string[];
  readonly kinds?: readonly string[];
  readonly touchInterval?: number;
  readonly prefix?: string;
  readonly extraColumns?: ExtraColumns;
};

export const apiKeysSqlOptions: BlockOptionsSchema<ApiKeysSqlOptions> =
  blockOptions<ApiKeysSqlOptions>({
    scopes: option.unknown<"catalog" | readonly string[]>(),
    kinds: option.strings(),
    touchInterval: option.number({ default: 60 }),
    prefix: option.string({ default: "bs" }),
    extraColumns: option.extraColumns(),
  });
