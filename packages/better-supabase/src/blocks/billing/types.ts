import type { BlockEventType } from "../../core/block-events.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { EventSink } from "../../events/index.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";
import type { StripeSource, StripeTaxId } from "../stripe.ts";
import type { BillingEvents } from "./events.ts";

export interface BillingOptions extends BlockTemporalOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Billing>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly stripe: StripeSource;
  /**
   * A service-role transport: linking customers and reading seats are granted
   * to `service_role` only.
   */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `betterSupabase.events`, for `billing.*` block events. */
  readonly events?: EventHub;
  /**
   * Where subscription state lives, matching
   * `blocks.billing.options.subscriptions`. `webhook` stores every
   * `customer.subscription.*` event handled by `handleStripeEvent` in
   * `billing_subscriptions`, newest event wins, and makes `checkout` refuse a
   * tenant that is already subscribed. Default `sync-engine`.
   */
  readonly subscriptions?: "sync-engine" | "webhook";
  /**
   * Names the provider that already bills the tenant outside Stripe, such as a
   * marketplace. `checkout` then fails with `BILLING_EXTERNAL` and the provider
   * in the message. In webhook mode the SQL hook
   * `public.billing_external_provider(tenant)` does the same.
   */
  readonly external?: (
    tenant: string,
  ) => string | undefined | Promise<string | undefined>;
  /**
   * The per-seat price `syncSeats` updates; default the subscription's first
   * item.
   */
  readonly seatPrice?: string;
  /** Stripe `proration_behavior` for seat changes, default `create_prorations`. */
  readonly prorationBehavior?: "create_prorations" | "none" | "always_invoice";
  /**
   * Invalidates the cached sessions of a customer's members after a plan change
   * (`entitlementMembers`), so their next request reads the new entitlements.
   * Needs the `entitlements` module.
   */
  readonly sessions?: {
    readonly sql: SqlClient;
    readonly invalidate: (userId: string) => void;
  };
  /**
   * Bills tenants as Stripe Accounts v2 accounts with the `customer`
   * configuration instead of v1 customers. `checkout` creates or reuses the
   * tenant's account and passes it as `customer_account` to Checkout, as does
   * `portal`. Stripe creates the account's linked customer at the first
   * checkout, and `handleStripeEvent` records it. A tenant that already has a
   * v1 customer keeps it. Needs `v2.core.accounts` on the Stripe client.
   * Default `false`.
   */
  readonly customerAccounts?: boolean | CustomerAccountOptions;
  /**
   * `ignore` skips Connect events (those with `event.account`, sent for a
   * connected account) in `handleStripeEvent`, for an endpoint or event
   * destination that receives both platform and connected account events while
   * the block bills on the platform. Default `handle`.
   */
  readonly connectEvents?: "handle" | "ignore";
}

/** `customerAccounts` in `createBilling`. */
export interface CustomerAccountOptions {
  /**
   * The tenant's existing Accounts v2 account, such as the connected account it
   * already sells through, or `undefined` to create one. The account needs the
   * `customer` configuration before Stripe bills it.
   */
  readonly resolve?: (
    tenant: string,
  ) => string | undefined | Promise<string | undefined>;
  /**
   * More `v2.core.accounts.create` parameters, merged deeply over the block's
   * (`contact_email`, `display_name`, `configuration.customer` and the tenant
   * in `metadata.organization_id`), or a function of the tenant and the details
   * that returns them.
   */
  readonly params?:
    | Readonly<Record<string, unknown>>
    | ((
        tenant: string,
        details: CustomerDetails,
      ) => Readonly<Record<string, unknown>>);
}

export interface CustomerDetails {
  readonly email?: string;
  readonly name?: string;
}

export interface CheckoutOptions extends CustomerDetails {
  /** A Stripe price id. Pass this or `plan`. */
  readonly price?: string;
  /**
   * A plan key from `blocks.billing.options.plans`, resolved to its Stripe
   * price in the app's plan catalog (with `interval` when plans have monthly
   * and yearly prices).
   */
  readonly plan?: string;
  readonly interval?: string;
  /** One of the plan's prices, from the catalog's `variant` column. */
  readonly variant?: string;
  /**
   * More line items, such as add-on packages next to the plan: each a price, or
   * a plan key with `interval` and `variant`. Quantity defaults to 1.
   */
  readonly items?: readonly CheckoutItem[];
  readonly successUrl: string;
  readonly cancelUrl?: string;
  /** A number, or `seats` for the tenant's seat count. Default 1. */
  readonly quantity?: number | "seats";
  /** Default `subscription`. */
  readonly mode?: "subscription" | "payment";
  /**
   * More Checkout Session parameters, merged deeply over the block's (nested
   * objects such as `metadata` merge, arrays replace). The customer,
   * `client_reference_id` and the tenant's `metadata.organization_id` always
   * stay.
   */
  readonly params?: Readonly<Record<string, unknown>>;
  readonly idempotencyKey?: string;
}

/** An extra Checkout line item. */
export interface CheckoutItem {
  readonly price?: string;
  readonly plan?: string;
  readonly interval?: string;
  readonly variant?: string;
  readonly quantity?: number;
}

export interface SubscriptionItem {
  readonly subscriptionId: string;
  readonly itemId: string;
  readonly price: string | undefined;
  readonly quantity: number;
  readonly status: string;
}

export interface BillingStatus {
  readonly customerId: string | undefined;
  /** The tenant's Accounts v2 account, when it is billed as one. */
  readonly accountId: string | undefined;
  readonly seats: number;
  readonly subscription: SubscriptionItem | undefined;
}

export interface SeatSync {
  readonly quantity: number;
  readonly previousQuantity: number | undefined;
  /** False when there is no subscription item or the quantity already matches. */
  readonly changed: boolean;
}

/** The parts of a Stripe event the block reads. */
export interface StripeEvent {
  readonly id: string;
  readonly type: string;
  /** The connected account a Connect event happened on. */
  readonly account?: string | null;
  /** Unix seconds; orders subscription events in webhook mode. */
  readonly created?: number;
  readonly data: { readonly object: unknown };
}

export interface StripeEventOutcome {
  /** The `billing.*` block event it emitted, if any. */
  readonly event: BlockEventType<BillingEvents> | undefined;
  readonly organizationId: string | undefined;
  readonly customerId: string | undefined;
  /** The event object's `customer_account`, for a tenant billed as an account. */
  readonly accountId: string | undefined;
  /** Members whose sessions were invalidated. */
  readonly invalidated: readonly string[];
}

/** A plan change: a price id, or a plan key from the catalog. */
export interface PlanChange {
  readonly price?: string;
  readonly plan?: string;
  readonly interval?: string;
  readonly variant?: string;
  /** Stripe `proration_behavior`, default `create_prorations`. */
  readonly prorationBehavior?: "create_prorations" | "none" | "always_invoice";
  /** Also clears a scheduled cancellation. Default true. */
  readonly resume?: boolean;
  readonly idempotencyKey?: string;
}

/**
 * A row of the Stripe Sync Engine's `stripe` schema as stored, such as an
 * invoice (`id`, `status`, `total`, `currency`, `hosted_invoice_url`) or a
 * payment method (`id`, `type`, `card`).
 */
export type StripeRow = Readonly<Record<string, unknown>>;

/**
 * A Sync Engine row with the tenant and customer it belongs to, from a platform
 * read.
 */
export interface TenantStripeRow {
  readonly organizationId: string;
  readonly customerId: string;
  readonly row: StripeRow;
}

/** A linked Stripe customer, from `billing_all_customers`. */
export interface BillingCustomer {
  readonly organizationId: string;
  readonly customerId: string;
  /** From the Sync Engine's `stripe.customers`; `undefined` before it syncs. */
  readonly email: string | undefined;
  readonly name: string | undefined;
  readonly created: Temporal.Instant | undefined;
}

export interface PlatformListOptions extends CursorPageOptions<number> {
  /** Only rows with this Stripe status, such as `active` or `open`. */
  readonly status?: string;
  /** Defaults to 100, at most 500. */
  readonly limit?: number;
  /** Only rows Stripe created before this (epoch seconds), for the next page. */
  readonly cursor?: number;
}

export interface BillingCustomerUpdate {
  readonly email?: string;
  readonly name?: string;
  readonly phone?: string;
  readonly address?: Readonly<Record<string, string>>;
  /** Stripe customer parameters merged over these, such as `invoice_settings`. */
  readonly params?: Readonly<Record<string, unknown>>;
}

export interface Billing {
  /** The tenant's Stripe customer, or `undefined` before the first checkout. */
  customer(organizationId: string): AsyncResult<string | undefined>;
  /**
   * The tenant's Stripe Accounts v2 account (`acct_`), or `undefined` when it
   * is not billed as one.
   */
  account(organizationId: string): AsyncResult<string | undefined>;
  /**
   * The tenant's customer, created in Stripe (with the tenant in `metadata`)
   * when there is none. With `customerAccounts`, a tenant without a customer
   * gets its account instead, and this fails with `not_found`
   * (`BILLING_CUSTOMER_PENDING`) until Stripe creates the account's customer at
   * the first checkout.
   */
  ensureCustomer(input: {
    organizationId: string;
    details?: CustomerDetails | undefined;
  }): AsyncResult<string>;
  /**
   * The tenant's Accounts v2 account: the linked one, the one
   * `customerAccounts.resolve` returns, or a new one with the `customer`
   * configuration (and the tenant in `metadata`), which it links.
   */
  ensureAccount(input: {
    organizationId: string;
    details?: CustomerDetails | undefined;
  }): AsyncResult<string>;
  checkout(input: {
    organizationId: string;
    options: CheckoutOptions;
  }): AsyncResult<{ readonly id: string; readonly url: string | undefined }>;
  /**
   * A subscription Checkout with a free trial of `days` days: `checkout` with
   * `subscription_data.trial_period_days` set (other `subscription_data` in
   * `params` stay). Stripe starts the subscription as `trialing`; the same
   * webhooks follow.
   */
  startTrial(input: {
    organizationId: string;
    options: Omit<CheckoutOptions, "mode"> & { readonly days: number };
  }): AsyncResult<{ readonly id: string; readonly url: string | undefined }>;
  /**
   * A customer portal session, for the tenant's account with
   * `customerAccounts`; `not_found` before the tenant has a customer or an
   * account.
   */
  portal(input: {
    organizationId: string;
    options: { readonly returnUrl: string };
  }): AsyncResult<{ readonly url: string }>;
  status(organizationId: string): AsyncResult<BillingStatus>;
  /**
   * The tenant's newest subscription as the Sync Engine stores it (every
   * column, with `items`), preferring an active one; `undefined` without one.
   * For `billing.read` in the tenant, or platform staff.
   */
  subscription(organizationId: string): AsyncResult<StripeRow | undefined>;
  /**
   * Every tenant's newest subscription, newest first, for platform staff
   * (`billing.read` in the platform scope) or a service transport.
   */
  allSubscriptions(
    options?: PlatformListOptions,
  ): AsyncResult<readonly TenantStripeRow[]>;
  /**
   * Every linked customer, with or without a subscription, by tenant, for
   * platform staff (`billing.read` in the platform scope) or a service
   * transport.
   */
  allCustomers(): AsyncResult<readonly BillingCustomer[]>;
  /**
   * Cancels the tenant's active subscription in Stripe now; `undefined` when it
   * has none. The `customer.subscription.deleted` webhook then emits
   * `billing.subscription_deleted`.
   */
  cancelSubscription(organizationId: string): AsyncResult<string | undefined>;
  /** Sets the seat item's quantity to the tenant's seat count. */
  syncSeats(
    input: { organizationId: string } & { readonly key?: string },
  ): AsyncResult<SeatSync>;
  /**
   * An outbox sink that syncs seats after `organization.member_*` and
   * `organization.role_changed` events: `outbox.relay('billing-seats',
   * billing.seatSink())`.
   */
  seatSink(): EventSink;
  /**
   * Moves the tenant's subscription item to another price (an upgrade or
   * downgrade). Needs a subscription; `not_found` otherwise. Admin consoles
   * call it with a service transport after their own permission check.
   */
  changePlan(input: {
    organizationId: string;
    change: PlanChange;
  }): AsyncResult<SubscriptionItem>;
  /**
   * Schedules (true) or clears (false) the cancellation at the end of the
   * period.
   */
  cancelAtPeriodEnd(input: {
    organizationId: string;
    cancel: boolean;
  }): AsyncResult<string>;
  /**
   * Every tenant's invoices, newest first, for platform staff (`billing.read`
   * in the platform scope) or a service transport.
   */
  allInvoices(
    options?: PlatformListOptions,
  ): AsyncResult<readonly TenantStripeRow[]>;
  /**
   * The tenant's invoices from the Sync Engine, newest first (`billing.read`,
   * or platform staff).
   */
  invoices(
    input: { organizationId: string } & { readonly limit?: number },
  ): AsyncResult<readonly StripeRow[]>;
  /** The tenant's payment methods from the Sync Engine (`billing.read`). */
  paymentMethods(organizationId: string): AsyncResult<readonly StripeRow[]>;
  /** Voids an open invoice of the tenant's customer. */
  voidInvoice(input: {
    organizationId: string;
    invoiceId: string;
  }): AsyncResult<string>;
  /** Marks an open invoice of the tenant's customer uncollectible. */
  markInvoiceUncollectible(input: {
    organizationId: string;
    invoiceId: string;
  }): AsyncResult<string>;
  /**
   * The billing contact as Stripe holds it, from the Sync Engine's customers
   * table.
   */
  customerDetails(organizationId: string): AsyncResult<StripeRow | undefined>;
  /**
   * The tenant customer's tax ids, `[]` before the tenant has a customer. From
   * Stripe by default, which needs `customers.listTaxIds` on the client; `{
   * from: "sync" }` reads the Sync Engine's `stripe.tax_ids` through
   * `billing_tax_ids` instead (`billing.read`, or platform staff).
   */
  taxIds(input: {
    organizationId: string;
    options?: { readonly from?: "stripe" | "sync" } | undefined;
  }): AsyncResult<readonly StripeTaxId[]>;
  /**
   * Adds a tax id (`{ type: 'eu_vat', value: 'DE123456789' }`) to the tenant's
   * customer, creating the customer first when there is none.
   */
  addTaxId(input: {
    organizationId: string;
    taxId: { readonly type: string; readonly value: string };
  }): AsyncResult<StripeTaxId>;
  /**
   * Removes a tax id from the tenant's customer; `not_found` before the tenant
   * has a customer.
   */
  removeTaxId(input: {
    organizationId: string;
    taxId: string;
  }): AsyncResult<string>;
  /** Updates the billing contact on the Stripe customer, the record for it. */
  updateCustomer(input: {
    organizationId: string;
    update: BillingCustomerUpdate;
  }): AsyncResult<string>;
  /**
   * Handles `checkout.session.completed` and `customer.subscription.*`: links
   * the customer, emits `billing.*` events and invalidates sessions. Any other
   * event with a `customer_account` of a linked tenant records the account's
   * customer; other events are ignored. Call it from `inbox.process`.
   */
  handleStripeEvent(event: unknown): AsyncResult<StripeEventOutcome>;
}
