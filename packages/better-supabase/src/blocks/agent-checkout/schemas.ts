import type { EntitySchema } from "../entity-schema.ts";
import type { CreateCheckoutSessionInput } from "./agent-checkout.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `createSession` takes, as a plain-JSON entity schema. */
export const checkoutSessionInputSchema: EntitySchema<
  Omit<CreateCheckoutSessionInput, "expiresAt">
> = entitySchema<Omit<CreateCheckoutSessionInput, "expiresAt">>({
  title: "CheckoutSessionInput",
  fields: {
    cartId: { kind: "string", minLength: 1 },
    protocol: { kind: "enum", values: ["acp", "ucp"] },
    idempotencyKey: {
      kind: "string",
      minLength: 1,
      maxLength: 255,
      description: "The agent's Idempotency-Key header.",
    },
  },
});
