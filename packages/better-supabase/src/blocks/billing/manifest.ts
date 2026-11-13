import type { BlockOf } from "../define-block.ts";
import type { BillingEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { CRON_SECRET_ENV, DATABASE_URL_ENV } from "../wiring.ts";
import { createBilling } from "./billing.ts";
import { billingEvents } from "./events.ts";
import { billingSqlOptions } from "./options.ts";

/** The `billing` block's manifest (ADR 0029). */
export const billingBlock: BlockOf<
  "billing",
  typeof createBilling,
  BillingEvents
> = defineBlock({
  name: "billing",
  sql: ["billing"],
  options: { billing: billingSqlOptions },
  events: billingEvents,
  create: createBilling,
  category: "commerce",
  entities: {
    billing: { mutability: "state-machine", emits: { create: false } },
  },
  description:
    "Each tenant's Stripe customer, seat counts (options.seatRoles) and the active subscription item from the Stripe Sync Engine, for createBilling(): checkout, the customer portal, seat sync and Stripe webhook handling.",
  recipes: ["plan-picker"],
  env: [
    {
      key: "STRIPE_SECRET_KEY",
      description:
        "Server-only: the Stripe secret key billing calls Stripe with.",
    },
    {
      key: "STRIPE_WEBHOOK_SECRET",
      description:
        "Server-only: the signing secret of the Stripe webhook endpoint.",
    },
    CRON_SECRET_ENV,
    DATABASE_URL_ENV,
  ],
  routes: ["stripe-webhook"],
  workers: [
    {
      name: "stripe-process",
      description:
        "Applies the Stripe events the webhook stored to subscriptions and invoices.",
      path: "/api/stripe/process",
      schedule: "* * * * *",
    },
  ],
});
