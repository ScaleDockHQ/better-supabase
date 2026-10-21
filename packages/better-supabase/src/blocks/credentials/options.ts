import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.credentials.options`. */
export type CredentialsSqlOptions = { readonly secretStorage?: string };

export const credentialsSqlOptions: BlockOptionsSchema<CredentialsSqlOptions> =
  blockOptions<CredentialsSqlOptions>({
    secretStorage: option.string({ default: "vault" }),
  });
