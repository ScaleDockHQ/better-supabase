import { type StripeClient, stripeClient } from "../blocks/stripe.ts";
import { memoized } from "../core/optional-peer.ts";

/**
 * The secret key and, optionally, the API version of the Stripe client to
 * create.
 */
export interface StripeFromKeyOptions {
  readonly secretKey: string;
  readonly apiVersion?: string;
}

/**
 * A `stripe` source for the billing, usage and commerce Stripe adapters that
 * creates the client from the `stripe` package once, on first use, with
 * Stripe's fetch HTTP client. The import names `stripe` literally, so bundlers
 * resolve it and file tracing ships it; `stripe` stays an optional peer.
 */
export function stripeFromKey<C extends object = StripeClient>(
  options: StripeFromKeyOptions,
): () => Promise<C> {
  return memoized(() => stripeClient<C>(options, () => import("stripe")));
}
