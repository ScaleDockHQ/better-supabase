import {
  createBilling,
  stripeInboxVerify,
} from "better-supabase/blocks/billing";
import { createWebhookInbox, sqlTransport } from "better-supabase/blocks/jobs";

import { postgres } from "@/lib/postgres";

/**
 * Stores each verified Stripe event once; the process route hands it to
 * billing.
 */
export const stripeInbox = createWebhookInbox({
  transport: sqlTransport(postgres.admin),
  source: "stripe",
  verify: stripeInboxVerify(process.env.STRIPE_WEBHOOK_SECRET ?? ""),
});

/**
 * The billing block on the service connection, which links customers and syncs
 * seats.
 */
export const billing = createBilling({
  stripe: { secretKey: process.env.STRIPE_SECRET_KEY ?? "" },
  transport: sqlTransport(postgres.admin),
});
