import type {
  OauthClientEventData,
  OauthGrantEventData,
  OauthServerEvents,
} from "./events.ts";
import type {
  OauthAuthorization,
  OauthClient,
  OauthClientAuthMethod,
  OauthClientMetadata,
  OauthGrant,
  OauthGrantType,
  OauthServer,
  OauthServerOptions,
  RegisteredOauthClient,
} from "./oauth-server.ts";

import { createOauthServer } from "./oauth-server.ts";

/** @deprecated Use `createOauthServer`. Removed in the next minor. */
export const createOAuthServer: typeof createOauthServer = createOauthServer;

/** @deprecated Use `OauthClientAuthMethod`. */
export type OAuthClientAuthMethod = OauthClientAuthMethod;

/** @deprecated Use `OauthGrantType`. */
export type OAuthGrantType = OauthGrantType;

/** @deprecated Use `OauthServerOptions`. */
export type OAuthServerOptions = OauthServerOptions;

/** @deprecated Use `OauthClientMetadata`. */
export type OAuthClientMetadata = OauthClientMetadata;

/** @deprecated Use `OauthClient`. */
export type OAuthClient = OauthClient;

/** @deprecated Use `RegisteredOauthClient`. */
export type RegisteredOAuthClient = RegisteredOauthClient;

/** @deprecated Use `OauthAuthorization`. */
export type OAuthAuthorization = OauthAuthorization;

/** @deprecated Use `OauthGrant`. */
export type OAuthGrant = OauthGrant;

/** @deprecated Use `OauthServer`. */
export type OAuthServer = OauthServer;

/** @deprecated Use `OauthClientEventData`. */
export type OAuthClientEventData = OauthClientEventData;

/** @deprecated Use `OauthGrantEventData`. */
export type OAuthGrantEventData = OauthGrantEventData;

/** @deprecated Use `OauthServerEvents`. */
export type OAuthServerEvents = OauthServerEvents;
