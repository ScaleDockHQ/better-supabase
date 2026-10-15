import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.credentials.options`. */
export type CredentialsSqlOptions = {
  readonly secretStorage?: string;
};

export const credentialsSqlOptions: BlockOptionsSchema<CredentialsSqlOptions> =
  blockOptions<CredentialsSqlOptions>({
    secretStorage: option.string({ default: "vault" }),
  });
