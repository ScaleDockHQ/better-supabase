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
  /** A service-role transport: linking customers and reading seats are granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `betterSupabase.events`, for `billing.*` block events. */
  readonly events?: EventHub;
  /**
   * Where subscription state lives, matching `blocks.billing.options.subscriptions`.
   * `webhook` stores every `customer.subscription.*` event handled by
   * `handleStripeEvent` in `billing_subscriptions`, newest event wins, and
   * makes `checkout` refuse a tenant that is already subscribed. Default `sync-engine`.
   */
  readonly subscriptions?: "sync-engine" | "webhook";
  /**
   * Names the provider that already bills the tenant outside Stripe, such as
   * a marketplace. `checkout` then fails with `BILLING_EXTERNAL` and the
   * provider in the message. In webhook mode the SQL hook
   * `public.billing_external_provider(tenant)` does the same.
   */
  readonly external?: (
    tenant: string,
  ) => string | undefined | Promise<string | undefined>;
  /** The per-seat price `syncSeats` updates; default the subscription's first item. */
  readonly seatPrice?: string;
  /** Stripe `proration_behavior` for seat changes, default `create_prorations`. */
  readonly prorationBehavior?: "create_prorations" | "none" | "always_invoice";
  /**
   * Invalidates the cached sessions of a customer's members after a plan
   * change (`entitlementMembers`), so their next request reads the new
   * entitlements. Needs the `entitlements` module.
   */
  readonly sessions?: {
    readonly sql: SqlClient;
    readonly invalidate: (userId: string) => void;
  };
}

export interface CustomerDetails {
  readonly email?: string;
  readonly name?: string;
}

export interface CheckoutOptions extends CustomerDetails {
  /** A Stripe price id. Pass this or `plan`. */
  readonly price?: string;
  /**
   * A plan key from `blocks.billing.options.plans`, resolved to its
   * Stripe price in the app's plan catalog (with `interval` when plans have
   * monthly and yearly prices).
   */
  readonly plan?: string;
  readonly interval?: string;
  /** One of the plan's prices, from the catalog's `variant` column. */
  readonly variant?: string;
  /**
   * More line items, such as add-on packages next to the plan: each a
   * price, or a plan key with `interval` and `variant`. Quantity defaults to 1.
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
  /** Unix seconds; orders subscription events in webhook mode. */
  readonly created?: number;
  readonly data: { readonly object: unknown };
}

export interface StripeEventOutcome {
  /** The `billing.*` block event it emitted, if any. */
  readonly event: BlockEventType<BillingEvents> | undefined;
  readonly organizationId: string | undefined;
  readonly customerId: string | undefined;
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

/** A Sync Engine row with the tenant and customer it belongs to, from a platform read. */
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
  /** The tenant's customer, created in Stripe (with the tenant in `metadata`) when there is none. */
  ensureCustomer(
    organizationId: string,
    details?: CustomerDetails,
  ): AsyncResult<string>;
  checkout(
    organizationId: string,
    options: CheckoutOptions,
  ): AsyncResult<{ readonly id: string; readonly url: string | undefined }>;
  /** A customer portal session; `not_found` before the tenant has a customer. */
  portal(
    organizationId: string,
    options: { readonly returnUrl: string },
  ): AsyncResult<{ readonly url: string }>;
  status(organizationId: string): AsyncResult<BillingStatus>;
  /**
   * The tenant's newest subscription as the Sync Engine stores it (every
   * column, with `items`), preferring an active one; `undefined` without
   * one. For `billing.read` in the tenant, or platform staff.
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
   * Cancels the tenant's active subscription in Stripe now; `undefined`
   * when it has none. The `customer.subscription.deleted` webhook then
   * emits `billing.subscription_deleted`.
   */
  cancelSubscription(organizationId: string): AsyncResult<string | undefined>;
  /** Sets the seat item's quantity to the tenant's seat count. */
  syncSeats(
    organizationId: string,
    options?: { readonly key?: string },
  ): AsyncResult<SeatSync>;
  /**
   * An outbox sink that syncs seats after `organization.member_*` and
   * `organization.role_changed` events: `outbox.relay('billing-seats', billing.seatSink())`.
   */
  seatSink(): EventSink;
  /**
   * Moves the tenant's subscription item to another price (an upgrade or
   * downgrade). Needs a subscription; `not_found` otherwise. Admin consoles
   * call it with a service transport after their own permission check.
   */
  changePlan(
    organizationId: string,
    change: PlanChange,
  ): AsyncResult<SubscriptionItem>;
  /** Schedules (true) or clears (false) the cancellation at the end of the period. */
  cancelAtPeriodEnd(
    organizationId: string,
    cancel: boolean,
  ): AsyncResult<string>;
  /**
   * Every tenant's invoices, newest first, for platform staff (`billing.read`
   * in the platform scope) or a service transport.
   */
  allInvoices(
    options?: PlatformListOptions,
  ): AsyncResult<readonly TenantStripeRow[]>;
  /** The tenant's invoices from the Sync Engine, newest first (`billing.read`, or platform staff). */
  invoices(
    organizationId: string,
    options?: { readonly limit?: number },
  ): AsyncResult<readonly StripeRow[]>;
  /** The tenant's payment methods from the Sync Engine (`billing.read`). */
  paymentMethods(organizationId: string): AsyncResult<readonly StripeRow[]>;
  /** Voids an open invoice of the tenant's customer. */
  voidInvoice(organizationId: string, invoiceId: string): AsyncResult<string>;
  /** Marks an open invoice of the tenant's customer uncollectible. */
  markInvoiceUncollectible(
    organizationId: string,
    invoiceId: string,
  ): AsyncResult<string>;
  /** The billing contact as Stripe holds it, from the Sync Engine's customers table. */
  customerDetails(organizationId: string): AsyncResult<StripeRow | undefined>;
  /**
   * The tenant customer's tax ids, `[]` before the tenant has a customer.
   * From Stripe by default, which needs `customers.listTaxIds` on the
   * client; `{ from: "sync" }` reads the Sync Engine's `stripe.tax_ids`
   * through `billing_tax_ids` instead (`billing.read`, or platform staff).
   */
  taxIds(
    organizationId: string,
    options?: { readonly from?: "stripe" | "sync" },
  ): AsyncResult<readonly StripeTaxId[]>;
  /**
   * Adds a tax id (`{ type: 'eu_vat', value: 'DE123456789' }`) to the
   * tenant's customer, creating the customer first when there is none.
   */
  addTaxId(
    organizationId: string,
    taxId: { readonly type: string; readonly value: string },
  ): AsyncResult<StripeTaxId>;
  /** Removes a tax id from the tenant's customer; `not_found` before the tenant has a customer. */
  removeTaxId(organizationId: string, taxId: string): AsyncResult<string>;
  /** Updates the billing contact on the Stripe customer, the record for it. */
  updateCustomer(
    organizationId: string,
    update: BillingCustomerUpdate,
  ): AsyncResult<string>;
  /**
   * Handles `checkout.session.completed` and `customer.subscription.*`:
   * links the customer, emits `billing.*` events and invalidates sessions.
   * Other events are ignored. Call it from `inbox.process`.
   */
  handleStripeEvent(event: unknown): AsyncResult<StripeEventOutcome>;
}
