import type { BlockOf } from "../define-block.ts";
import type { AgentCheckoutEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createAgentCheckout } from "./agent-checkout.ts";
import { agentCheckoutEvents } from "./events.ts";
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
});
