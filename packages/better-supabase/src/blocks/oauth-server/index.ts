export {
  type AuthorizationCodeRedemption,
  type AuthorizationCodeRequest,
  createOauthServer,
  type DeviceCodePoll,
  type DeviceRequest,
  type IssuedAuthorizationCode,
  type IssuedDeviceCode,
  type ListGrantsOptions,
  type OauthAuthorization,
  type OauthClient,
  type OauthClientAuthMethod,
  type OauthClientMetadata,
  type OauthGrant,
  type OauthGrantType,
  type OauthServer,
  type OauthServerOptions,
  type RegisterClientOptions,
  type RegisteredOauthClient,
  type RevokeTokenOptions,
} from "./oauth-server.ts";

export { sqlTransport } from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { oauthServerBlock } from "./manifest.ts";

export { oauthServerEvents } from "./events.ts";

export type {
  OauthClientEventData,
  OauthGrantEventData,
  OauthServerEvents,
} from "./events.ts";

// The OAuth spellings stay exported for one minor; re-exporting a deprecated
// name is the point here (13 findings).
/* oxlint-disable typescript/no-deprecated */
export {
  createOAuthServer,
  type OAuthAuthorization,
  type OAuthClient,
  type OAuthClientAuthMethod,
  type OAuthClientEventData,
  type OAuthClientMetadata,
  type OAuthGrant,
  type OAuthGrantEventData,
  type OAuthGrantType,
  type OAuthServer,
  type OAuthServerEvents,
  type OAuthServerOptions,
  type RegisteredOAuthClient,
} from "./deprecated.ts";
/* oxlint-enable typescript/no-deprecated */
