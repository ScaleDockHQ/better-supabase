import type { BlockOf } from "../define-block.ts";
import type { OAuthServerEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { oauthServerEvents } from "./events.ts";
import { createOAuthServer } from "./oauth-server.ts";
import { oauthServerSqlOptions } from "./options.ts";

/** The `oauth-server` block's manifest (ADR 0029). */
export const oauthServerBlock: BlockOf<
  "oauth-server",
  typeof createOAuthServer,
  OAuthServerEvents
> = defineBlock({
  name: "oauth-server",
  sql: ["oauth-server"],
  options: {
    "oauth-server": oauthServerSqlOptions,
  },
  events: oauthServerEvents,
  create: createOAuthServer,
  category: "developer",
});
