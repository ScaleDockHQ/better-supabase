import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `oauth_client.*`: the client id, never its secret. */
export interface OAuthClientEventData {
  readonly clientId: string;
}

/** `oauth_grant.*`: who granted which client access. */
export interface OAuthGrantEventData {
  readonly grantId: string;
  readonly userId: string;
  readonly clientId: string;
}

/** The events of the `oauth-server` block: type to data. */
export type OauthServerEvents = {
  readonly "oauth_client.registered": OAuthClientEventData;
  readonly "oauth_client.deleted": OAuthClientEventData;
  readonly "oauth_grant.created": OAuthGrantEventData;
  readonly "oauth_grant.revoked": OAuthGrantEventData;
};

/** The `oauth-server` block's event types, for its manifest and `onBlockEvent`. */
export const oauthServerEvents: Events<OauthServerEvents> = defineEvents({
  "oauth_client.registered": event<OAuthClientEventData>(),
  "oauth_client.deleted": event<OAuthClientEventData>(),
  "oauth_grant.created": event<OAuthGrantEventData>(),
  "oauth_grant.revoked": event<OAuthGrantEventData>(),
});
