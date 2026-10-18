import type { BlockOf } from "../define-block.ts";
import type { ConnectorsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createConnectors } from "./connectors.ts";
import { connectorsEvents } from "./events.ts";
import { connectorsSqlOptions } from "./options.ts";

/** The `connectors` block's manifest (ADR 0029). */
export const connectorsBlock: BlockOf<
  "connectors",
  typeof createConnectors,
  ConnectorsEvents
> = defineBlock({
  name: "connectors",
  sql: ["connectors"],
  options: {
    connectors: connectorsSqlOptions,
  },
  events: connectorsEvents,
  create: createConnectors,
  category: "automation",
  recipes: ["connector-setup"],
});
