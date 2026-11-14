import { stripeInbox } from "@/features/billing/billing-stripe";

/**
 * Stripe's webhook endpoint: verifies the signature and stores the event once.
 * `/api/stripe/process` hands the stored events to the billing block.
 */
export function POST(request: Request): Promise<Response> | Response {
  const inbox = stripeInbox();

  if (!inbox) {
    return new Response(
      "Set STRIPE_WEBHOOK_SECRET and DATABASE_URL to receive Stripe events",
      { status: 503 },
    );
  }

  return inbox.receive(request);
}
