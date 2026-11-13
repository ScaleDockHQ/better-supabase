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
  options: { connectors: connectorsSqlOptions },
  events: connectorsEvents,
  create: createConnectors,
  category: "automation",
  entities: {
    connector_server: {
      mutability: "editable",
      emits: { update: false, delete: false },
    },
  },
  concerns: ["lifecycle"],
  description:
    "MCP servers per tenant with no, per-user OAuth or header auth; per-user grants that hold only a credential_ref; MCP sessions per chat; and tool list fingerprints that hold a changed list until an admin approves it.",
  recipes: ["connector-setup"],
});
