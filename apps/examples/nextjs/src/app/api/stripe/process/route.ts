import { env } from "@/env";
import { stripeBilling, stripeInbox } from "@/features/billing/billing-stripe";

/**
 * Hands the stored Stripe events to the billing block. Call it from a cron
 * (Vercel Cron sends `Authorization: Bearer $CRON_SECRET`); a failed event
 * stays in the inbox for the next run.
 */
export async function GET(request: Request): Promise<Response> {
  const secret = env.CRON_SECRET;

  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const inbox = stripeInbox();
  const billing = stripeBilling();

  if (!inbox || !billing) {
    return new Response(
      "Set STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET and DATABASE_URL to process Stripe events",
      { status: 503 },
    );
  }

  const result = await inbox.process({
    handler: (message) => billing.handleStripeEvent(message.payload).orThrow(),
  });

  return Response.json(result);
}
