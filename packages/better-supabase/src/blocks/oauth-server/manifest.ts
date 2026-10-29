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
});
