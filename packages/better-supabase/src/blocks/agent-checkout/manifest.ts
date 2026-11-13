import type { BlockOf } from "../define-block.ts";
import type { AgentCheckoutEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAgentCheckout } from "./agent-checkout.ts";
import { agentCheckoutEvents } from "./events.ts";
import {
  agentMandateListSurface,
  checkoutSessionListSurface,
} from "./lists.ts";
import { checkoutSessionInputSchema } from "./schemas.ts";

/** The `agent-checkout` block's manifest (ADR 0029). */
export const agentCheckoutBlock: BlockOf<
  "agent-checkout",
  typeof createAgentCheckout,
  AgentCheckoutEvents
> = defineBlock({
  name: "agent-checkout",
  sql: ["agent-checkout"],
  events: agentCheckoutEvents,
  schemas: { checkout_session: { input: checkoutSessionInputSchema } },
  create: createAgentCheckout,
  recipes: [],
  category: "commerce",
  entities: {
    checkout_session: {
      ...checkoutSessionListSurface,
      mutability: "editable",
      emits: { create: true, update: true },
    },
    agent_mandate: {
      ...agentMandateListSurface,
      mutability: "state-machine",
      emits: { create: true },
    },
  },
  concerns: ["lifecycle"],
  description:
    "ACP and UCP checkout sessions over an orders cart with idempotency keys, and AP2 checkout mandates verified with signing keys and used once.",
});
