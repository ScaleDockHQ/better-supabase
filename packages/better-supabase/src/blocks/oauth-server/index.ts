export {
  type AuthorizationCodeRedemption,
  type AuthorizationCodeRequest,
  // eslint-disable-next-line typescript/no-deprecated -- the deprecated alias is re-exported for one minor.
  createOAuthServer,
  createOauthServer,
  type DeviceCodePoll,
  type DeviceRequest,
  type IssuedAuthorizationCode,
  type IssuedDeviceCode,
  type ListGrantsOptions,
  type OAuthAuthorization,
  type OAuthClient,
  type OAuthClientAuthMethod,
  type OAuthClientMetadata,
  type OAuthGrant,
  type OAuthGrantType,
  type OauthServer,
  type OauthServerOptions,
  type RegisterClientOptions,
  type RegisteredOAuthClient,
  type RevokeTokenOptions,
} from "./oauth-server.ts";

export { sqlTransport } from "../../core/block-transport.ts";

export type { BlockTransport } from "../../core/block-transport.ts";

export { oauthServerBlock } from "./manifest.ts";

export { oauthServerEvents } from "./events.ts";

export type {
  OAuthClientEventData,
  OAuthGrantEventData,
  OauthServerEvents,
} from "./events.ts";
