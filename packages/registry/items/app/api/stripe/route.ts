import "server-only";
import { stripeInbox } from "@/lib/stripe";

/** Stripe's webhook endpoint: verifies the signature and stores the event once. */
export const POST = (request: Request): Promise<Response> =>
  stripeInbox.receive(request);
