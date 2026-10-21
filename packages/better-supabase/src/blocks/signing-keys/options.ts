import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.signing-keys.options`. */
export type SigningKeysSqlOptions = { readonly jwksGrace?: string };

export const signingKeysSqlOptions: BlockOptionsSchema<SigningKeysSqlOptions> =
  blockOptions<SigningKeysSqlOptions>({
    jwksGrace: option.string({ default: "5 minutes" }),
  });
