import "server-only";
import { billing, stripeInbox } from "@/lib/stripe";

/**
 * Hands the stored Stripe events to the billing block. Call it from a cron that
 * sends `Authorization: Bearer <CRON_SECRET>`; a failed event stays in the
 * inbox for the next run.
 */
export async function GET(request: Request): Promise<Response> {
  const secret = process.env.CRON_SECRET;

  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const result = await stripeInbox.process((message) =>
    billing.handleStripeEvent(message.payload).orThrow(),
  );

  return Response.json(result);
}
