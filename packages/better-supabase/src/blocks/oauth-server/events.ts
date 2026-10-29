import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `oauth_client.*`: the client id, never its secret. */
export interface OauthClientEventData {
  readonly clientId: string;
}

/** `oauth_grant.*`: who granted which client access. */
export interface OauthGrantEventData {
  readonly grantId: string;
  readonly userId: string;
  readonly clientId: string;
}

/** The events of the `oauth-server` block: type to data. */
export type OauthServerEvents = {
  readonly "oauth_client.registered": OauthClientEventData;
  readonly "oauth_client.deleted": OauthClientEventData;
  readonly "oauth_grant.created": OauthGrantEventData;
  readonly "oauth_grant.revoked": OauthGrantEventData;
};

/** The `oauth-server` block's event types, for its manifest and `onBlockEvent`. */
export const oauthServerEvents: Events<OauthServerEvents> = defineEvents({
  "oauth_client.registered": event<OauthClientEventData>(),
  "oauth_client.deleted": event<OauthClientEventData>(),
  "oauth_grant.created": event<OauthGrantEventData>(),
  "oauth_grant.revoked": event<OauthGrantEventData>(),
});
