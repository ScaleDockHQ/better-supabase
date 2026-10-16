import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.api-keys.options`. */
export type ApiKeysSqlOptions = {
  readonly scopes?: "catalog" | readonly string[];
  readonly touchInterval?: number;
  readonly prefix?: string;
  readonly extraColumns?: unknown;
};

export const apiKeysSqlOptions: BlockOptionsSchema<ApiKeysSqlOptions> =
  blockOptions<ApiKeysSqlOptions>({
    scopes: option.unknown<"catalog" | readonly string[]>(),
    touchInterval: option.number({ default: 60 }),
    prefix: option.string({ default: "bs" }),
    extraColumns: option.unknown(),
  });
