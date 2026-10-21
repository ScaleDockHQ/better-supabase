import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.oauth-server.options`. */
export type OAuthServerSqlOptions = {
  /**
   * The pattern a client id must match: a regular expression, or `"slug"` for
   * lower-case slugs such as `acme-cli`. The default accepts the 22-character
   * ids `registerClient` generates and any `[A-Za-z0-9._~-]{8,128}` id.
   */
  readonly clientIdPattern?: string;
};

export const oauthServerSqlOptions: BlockOptionsSchema<OAuthServerSqlOptions> =
  blockOptions<OAuthServerSqlOptions>({ clientIdPattern: option.string() });
