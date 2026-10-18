import type { BlockOf } from "../define-block.ts";
import type { OAuthServerEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { oauthServerEvents } from "./events.ts";
import { createOAuthServer } from "./oauth-server.ts";

/** The `oauth-server` block's manifest (ADR 0029). */
export const oauthServerBlock: BlockOf<
  "oauth-server",
  typeof createOAuthServer,
  OAuthServerEvents
> = defineBlock({
  name: "oauth-server",
  sql: ["oauth-server"],
  events: oauthServerEvents,
  create: createOAuthServer,
  category: "developer",
});
