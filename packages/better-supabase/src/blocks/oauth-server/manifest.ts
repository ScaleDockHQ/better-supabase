import type { BlockOf } from "../define-block.ts";
import type { OauthServerEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { oauthServerEvents } from "./events.ts";
import { createOauthServer } from "./oauth-server.ts";
import { oauthServerSqlOptions } from "./options.ts";

/** The `oauth-server` block's manifest (ADR 0029). */
export const oauthServerBlock: BlockOf<
  "oauth-server",
  typeof createOauthServer,
  OauthServerEvents
> = defineBlock({
  name: "oauth-server",
  sql: ["oauth-server"],
  options: { "oauth-server": oauthServerSqlOptions },
  events: oauthServerEvents,
  create: createOauthServer,
  category: "developer",
  entities: {
    oauth_client: {
      mutability: "editable",
      emits: { update: false, delete: true },
    },
    oauth_grant: { mutability: "state-machine", emits: { create: true } },
  },
  description:
    "Storage for an OAuth 2.1 authorization server: registered clients (RFC 7591) with hashed secrets, a grant per user and client, single-use authorization codes bound to a PKCE S256 challenge, device codes (RFC 8628) and a revocation list of access token jtis. It issues no tokens. createOauthServer() in better-supabase/blocks/oauth-server hashes secrets and checks PKCE, and its isRevoked plugs into accessTokenResolver.",
});
