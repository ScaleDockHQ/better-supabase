/**
 * The part of the Stripe SDK (`stripe`, an optional peer) the billing and
 * usage blocks call, typed structurally so the blocks never import it.
 */
export interface StripeClient {
  readonly customers: {
    create(params: {
      readonly email?: string;
      readonly name?: string;
      readonly metadata?: Readonly<Record<string, string>>;
    }): Promise<{ readonly id: string }>;
    /** Used by `billing.updateCustomer`. */
    update?(
      id: string,
      params: Readonly<Record<string, unknown>>,
    ): Promise<{ readonly id: string }>;
  };
  readonly checkout: {
    readonly sessions: {
      create(
        params: Readonly<Record<string, unknown>>,
        options?: { readonly idempotencyKey?: string },
      ): Promise<{ readonly id: string; readonly url: string | null }>;
    };
  };
  readonly billingPortal: {
    readonly sessions: {
      create(params: {
        readonly customer: string;
        readonly return_url?: string;
      }): Promise<{ readonly id: string; readonly url: string }>;
    };
  };
  readonly subscriptionItems: {
    update(
      id: string,
      params: {
        readonly quantity: number;
        readonly proration_behavior?: string;
      },
      options?: { readonly idempotencyKey?: string },
    ): Promise<{ readonly id: string; readonly quantity?: number | null }>;
  };
  readonly subscriptions: {
    cancel(id: string): Promise<{ readonly id: string }>;
    /** Used by `billing.changePlan` and `billing.cancelAtPeriodEnd`. */
    update?(
      id: string,
      params: Readonly<Record<string, unknown>>,
      options?: { readonly idempotencyKey?: string },
    ): Promise<{ readonly id: string }>;
  };
  /** Used by `billing.voidInvoice` and `billing.markInvoiceUncollectible`. */
  readonly invoices?: {
    voidInvoice(
      id: string,
    ): Promise<{ readonly id: string; readonly status?: string | null }>;
    markUncollectible(
      id: string,
    ): Promise<{ readonly id: string; readonly status?: string | null }>;
  };
  readonly billing: {
    readonly meterEvents: {
      create(
        params: {
          readonly event_name: string;
          readonly payload: Readonly<Record<string, string>>;
          readonly identifier?: string;
          readonly timestamp?: number;
        },
        options?: { readonly idempotencyKey?: string },
      ): Promise<unknown>;
    };
  };
  readonly webhooks: {
    constructEventAsync(
      payload: string,
      header: string,
      secret: string,
    ): Promise<{
      readonly id: string;
      readonly type: string;
      readonly data: { readonly object: unknown };
    }>;
  };
}

/** A Stripe client, or the secret key to create one from the `stripe` package. */
export type StripeSource =
  | StripeClient
  | { readonly secretKey: string; readonly apiVersion?: string };

interface StripeModule {
  readonly default: {
    new (
      key: string,
      options: { readonly httpClient: unknown; readonly apiVersion?: string },
    ): StripeClient;
    createFetchHttpClient(): unknown;
  };
}

const isModule = (value: unknown): value is StripeModule =>
  typeof value === "object" &&
  value !== null &&
  "default" in value &&
  typeof value.default === "function" &&
  "createFetchHttpClient" in value.default;

/**
 * Loads `stripe` on first use. The specifier is a variable so bundlers leave
 * the optional peer out of apps that pass their own client; a missing
 * install returns `undefined` and the caller explains how to add it.
 */
async function loadStripeModule(): Promise<unknown> {
  const specifier = "stripe";
  try {
    return await import(specifier);
  } catch {
    return undefined;
  }
}

/**
 * The client `source` names: itself, or one created with Stripe's fetch HTTP
 * client so it runs on every WinterTC runtime.
 */
export async function stripeClient(
  source: StripeSource,
  load: () => Promise<unknown> = loadStripeModule,
): Promise<StripeClient> {
  if (!("secretKey" in source)) return source;
  const loaded = await load();
  if (!isModule(loaded)) {
    throw new TypeError(
      "The billing and usage blocks need the stripe package: pnpm add stripe, or pass a Stripe client as `stripe`",
    );
  }
  const Stripe = loaded.default;
  return new Stripe(source.secretKey, {
    httpClient: Stripe.createFetchHttpClient(),
    ...(source.apiVersion === undefined
      ? {}
      : { apiVersion: source.apiVersion }),
  });
}

/** Resolves the client once, on first use. */
export function lazyStripe(source: StripeSource): () => Promise<StripeClient> {
  let client: Promise<StripeClient> | undefined;
  return () => (client ??= stripeClient(source));
}
