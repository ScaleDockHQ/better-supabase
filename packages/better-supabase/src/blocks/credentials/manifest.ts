import type { Block } from "../define-block.ts";
import type { CredentialsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { credentialsEvents } from "./events.ts";
import { credentialsSqlOptions } from "./options.ts";

/** The `credentials` block's manifest (ADR 0029). */
export const credentialsBlock: Block<
  "credentials",
  never,
  never,
  CredentialsEvents
> = defineBlock({
  name: "credentials",
  sql: ["credentials"],
  options: {
    credentials: credentialsSqlOptions,
  },
  events: credentialsEvents,
  category: "developer",
  recipes: ["connector-setup"],
});
