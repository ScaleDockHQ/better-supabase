import "server-only";
import {
  createBilling,
  stripeInboxVerify,
} from "better-supabase/blocks/billing";
import { createWebhookInbox, sqlTransport } from "better-supabase/blocks/queue";
import { createPostgres } from "better-supabase/postgres";

import { env } from "@/env";

type Billing = ReturnType<typeof createBilling>;

type StripeInbox = ReturnType<typeof createWebhookInbox>;

let pool: ReturnType<typeof createPostgres> | undefined;

/**
 * The service connection of the billing block and the webhook inbox
 * (`better_supabase.*` is not on the Data API). `undefined` without
 * `DATABASE_URL` or `WORKFLOW_POSTGRES_URL`.
 */
function connection() {
  const connectionString = env.DATABASE_URL ?? env.WORKFLOW_POSTGRES_URL;

  if (!connectionString) {
    return;
  }

  pool ??= createPostgres({ connectionString, max: 3 });

  return pool;
}

let inbox: StripeInbox | undefined;
let billing: Billing | undefined;

/**
 * Stores each verified Stripe event once; the process route hands it to
 * billing. `undefined` until `STRIPE_WEBHOOK_SECRET` and a database connection
 * are set.
 */
export function stripeInbox(): StripeInbox | undefined {
  const postgres = connection();

  if (!postgres || !env.STRIPE_WEBHOOK_SECRET) {
    return;
  }

  inbox ??= createWebhookInbox({
    transport: sqlTransport(postgres.admin),
    source: "stripe",
    verify: stripeInboxVerify(env.STRIPE_WEBHOOK_SECRET),
  });

  return inbox;
}

/**
 * The billing block on the service connection, which links customers, syncs
 * seats and opens Checkout. `undefined` until `STRIPE_SECRET_KEY` and a
 * database connection are set.
 */
export function stripeBilling(): Billing | undefined {
  const postgres = connection();

  if (!postgres || !env.STRIPE_SECRET_KEY) {
    return;
  }

  billing ??= createBilling({
    stripe: { secretKey: env.STRIPE_SECRET_KEY },
    transport: sqlTransport(postgres.admin),
  });

  return billing;
}

/** The Stripe price a plan bills with, from the environment. */
export function priceOf(plan: string): string | undefined {
  switch (plan) {
    case "pro": {
      return env.STRIPE_PRICE_PRO;
    }

    case "enterprise": {
      return env.STRIPE_PRICE_ENTERPRISE;
    }

    default: {
      return;
    }
  }
}

/** The plan key whose Stripe price is `price`. */
export function planOfPrice(price: string): string | undefined {
  return ["pro", "enterprise"].find((plan) => priceOf(plan) === price);
}
