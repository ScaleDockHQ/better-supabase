import type { Block } from "../define-block.ts";
import type { CredentialsEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { credentialsEvents } from "./events.ts";

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
    credentials: optionKeys(["secretStorage"]),
  },
  events: credentialsEvents,
  category: "platform",
});
