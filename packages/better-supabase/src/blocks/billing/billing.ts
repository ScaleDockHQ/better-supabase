import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { EventSink } from "../../events/index.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import {
  type BillingEventData,
  type BlockEventType,
  emitBlockEvent,
} from "../../core/block-events.ts";
import { dbError } from "../../core/errors.ts";
import {
  AsyncResult,
  err,
  ok,
  type Result,
  toDbError,
} from "../../core/result.ts";
import { entitlementMembers } from "../entitlements/entitlements.ts";
import {
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  textOf,
} from "../shared.ts";
import { lazyStripe, type StripeClient, type StripeSource } from "../stripe.ts";

export interface BillingOptions {
  readonly stripe: StripeSource;
  /** A service-role transport: linking customers and reading seats are granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.billing.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `betterSupabase.events`, for `billing.*` block events. */
  readonly events?: EventHub;
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
   * A plan key from `sql.modules.billing.options.plans`, resolved to its
   * Stripe price in the app's plan catalog (with `interval` when plans have
   * monthly and yearly prices).
   */
  readonly plan?: string;
  readonly interval?: string;
  readonly successUrl: string;
  readonly cancelUrl?: string;
  /** A number, or `seats` for the tenant's seat count. Default 1. */
  readonly quantity?: number | "seats";
  /** Default `subscription`. */
  readonly mode?: "subscription" | "payment";
  /** More Checkout Session parameters, merged over the block's. */
  readonly params?: Readonly<Record<string, unknown>>;
  readonly idempotencyKey?: string;
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
  readonly data: { readonly object: unknown };
}

export interface StripeEventOutcome {
  /** The `billing.*` block event it emitted, if any. */
  readonly event: BlockEventType | undefined;
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
  /** The tenant's invoices from the Sync Engine, newest first (`billing.read`). */
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

const ORGANIZATION_KEY = "organization_id";

const SEAT_EVENT =
  /(?:^|\.)organization\.(?:member_added|member_removed|member_left|role_changed)$/;

function subscriptionItemOf(value: unknown): SubscriptionItem | undefined {
  if (!isRecord(value)) return undefined;
  return {
    subscriptionId: textOf(value["subscription"]),
    itemId: textOf(value["item"]),
    price: optionalText(value["price"]),
    quantity: Number(value["quantity"] ?? 0),
    status: textOf(value["status"]),
  };
}

const customerIdOf = (value: unknown): string | undefined => {
  if (typeof value === "string") return value;
  return isRecord(value) ? optionalText(value["id"]) : undefined;
};

const metadataTenant = (
  object: Readonly<Record<string, unknown>>,
): string | undefined => {
  const metadata = object["metadata"];
  return isRecord(metadata)
    ? optionalText(metadata[ORGANIZATION_KEY])
    : undefined;
};

function isStripeEvent(value: unknown): value is StripeEvent {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    typeof value["type"] === "string" &&
    isRecord(value["data"])
  );
}

/** Stripe calls as results: a thrown Stripe error becomes a `DbError`. */
function stripeCall<T>(work: () => Promise<T>): AsyncResult<T> {
  return AsyncResult.from(async () => {
    try {
      return ok(await work());
    } catch (cause) {
      return err(toDbError(cause));
    }
  });
}

/** Stripe customers, checkout, the portal and seat sync over the `billing` module. */
export function createBilling(options: BillingOptions): Billing {
  const call = blockCall(options.transport, options.schema, options.mappers);
  const stripe = lazyStripe(options.stripe);
  const withStripe = <T>(
    work: (client: StripeClient) => Promise<T>,
  ): AsyncResult<T> => stripeCall(async () => work(await stripe()));

  const emit = (
    type: BlockEventType & `billing.${string}`,
    data: BillingEventData,
  ): void => {
    if (!options.events) return;
    emitBlockEvent(options.events, type, data, {
      tenant: data.organizationId,
      subject: `organizations/${data.organizationId}`,
    });
  };

  const customer = (organizationId: string): AsyncResult<string | undefined> =>
    call("billing_customer", { tenant: organizationId }, optionalText);

  const link = (
    organizationId: string,
    customerId: string,
  ): AsyncResult<string> =>
    call(
      "link_billing_customer",
      { tenant: organizationId, customer: customerId },
      textOf,
    );

  const ensureCustomer = (
    organizationId: string,
    details: CustomerDetails = {},
  ): AsyncResult<string> =>
    customer(organizationId).andThen(async (existing) => {
      if (existing !== undefined) return ok(existing);
      const created = await withStripe((client) =>
        client.customers.create({
          ...(details.email === undefined ? {} : { email: details.email }),
          ...(details.name === undefined ? {} : { name: details.name }),
          metadata: { [ORGANIZATION_KEY]: organizationId },
        }),
      );
      if (!created.ok) return created;
      const linked = await link(organizationId, created.data.id);
      if (linked.ok && linked.data === created.data.id) {
        emit("billing.customer_linked", {
          organizationId,
          customerId: linked.data,
        });
      }
      return linked;
    });

  const seats = (organizationId: string): AsyncResult<number> =>
    call("billing_seat_count", { tenant: organizationId }, (value) =>
      Number(value ?? 0),
    );

  const item = (
    organizationId: string,
  ): AsyncResult<SubscriptionItem | undefined> =>
    call(
      "billing_subscription_item",
      { tenant: organizationId, price: options.seatPrice },
      subscriptionItemOf,
    );

  const syncSeats = (
    organizationId: string,
    sync: { readonly key?: string } = {},
  ): AsyncResult<SeatSync> =>
    seats(organizationId).andThen(
      async (quantity): Promise<Result<SeatSync>> => {
        const current = await item(organizationId);
        if (!current.ok) return current;
        const found = current.data;
        if (found === undefined || found.quantity === quantity) {
          return ok({
            quantity,
            previousQuantity: found?.quantity,
            changed: false,
          });
        }
        const key = `seats:${found.itemId}:${String(found.quantity)}:${String(quantity)}:${sync.key ?? crypto.randomUUID()}`;
        const updated = await withStripe((client) =>
          client.subscriptionItems.update(
            found.itemId,
            {
              quantity,
              proration_behavior:
                options.prorationBehavior ?? "create_prorations",
            },
            { idempotencyKey: key },
          ),
        );
        if (!updated.ok) return updated;
        emit("billing.seats_synced", {
          organizationId,
          subscriptionId: found.subscriptionId,
          quantity,
          previousQuantity: found.quantity,
        });
        return ok({
          quantity,
          previousQuantity: found.quantity,
          changed: true,
        });
      },
    );

  const invalidate = async (event: StripeEvent): Promise<readonly string[]> => {
    if (!options.sessions) return [];
    const members = await entitlementMembers(options.sessions.sql, event);
    if (!members.ok) return [];
    for (const userId of members.data) options.sessions.invalidate(userId);
    return members.data;
  };

  const handleStripeEvent = (input: unknown): AsyncResult<StripeEventOutcome> =>
    AsyncResult.from(async () => {
      const ignored: StripeEventOutcome = {
        event: undefined,
        organizationId: undefined,
        customerId: undefined,
        invalidated: [],
      };
      if (!isStripeEvent(input)) return ok(ignored);
      const object = input.data.object;
      if (!isRecord(object)) return ok(ignored);
      const customerId = customerIdOf(object["customer"]);

      if (input.type === "checkout.session.completed") {
        const organizationId =
          metadataTenant(object) ?? optionalText(object["client_reference_id"]);
        if (organizationId === undefined || customerId === undefined) {
          return ok({ ...ignored, customerId });
        }
        const linked = await link(organizationId, customerId);
        if (!linked.ok) return linked;
        emit("billing.checkout_completed", {
          organizationId,
          customerId: linked.data,
          stripeEventId: input.id,
          ...(typeof object["subscription"] === "string"
            ? { subscriptionId: object["subscription"] }
            : {}),
        });
        return ok({
          event: "billing.checkout_completed",
          organizationId,
          customerId: linked.data,
          invalidated: [],
        });
      }

      const type = (
        {
          "customer.subscription.created": "billing.subscription_created",
          "customer.subscription.updated": "billing.subscription_updated",
          "customer.subscription.deleted": "billing.subscription_deleted",
        } as const
      )[input.type];
      if (type === undefined || customerId === undefined) return ok(ignored);

      const tenant = await call(
        "billing_customer_tenant",
        { customer: customerId },
        optionalText,
      );
      if (!tenant.ok) return tenant;
      let organizationId = tenant.data;
      const claimed = metadataTenant(object);
      if (organizationId === undefined && claimed !== undefined) {
        const linked = await link(claimed, customerId);
        if (!linked.ok) return linked;
        if (linked.data === customerId) organizationId = claimed;
      }
      if (organizationId === undefined) return ok({ ...ignored, customerId });
      emit(type, {
        organizationId,
        customerId,
        subscriptionId: textOf(object["id"]),
        stripeEventId: input.id,
        ...(typeof object["status"] === "string"
          ? { status: object["status"] }
          : {}),
      });
      return ok({
        event: type,
        organizationId,
        customerId,
        invalidated: await invalidate(input),
      });
    });

  const priceOf = (choice: {
    readonly price?: string;
    readonly plan?: string;
    readonly interval?: string;
  }): AsyncResult<string> => {
    const given = choice.price;
    if (given !== undefined)
      return AsyncResult.from<string>(() => Promise.resolve(ok(given)));
    if (choice.plan === undefined) {
      return AsyncResult.from<string>(() =>
        Promise.resolve(
          err(
            dbError("invalid_input", "Pass a price or a plan", {
              hint: "BILLING_PRICE_REQUIRED",
            }),
          ),
        ),
      );
    }
    const plan = choice.plan;
    return call(
      "billing_plan_price",
      { plan, billing_interval: choice.interval },
      optionalText,
    ).andThen((price) =>
      Promise.resolve(
        price === undefined
          ? err(
              dbError("not_found", `No price for plan "${plan}"`, {
                hint: "BILLING_PLAN_UNKNOWN",
              }),
            )
          : ok(price),
      ),
    );
  };

  const missing = (what: string): Result<never> =>
    err(
      dbError("invalid_request", `The Stripe client has no ${what}`, {
        hint: "BILLING_STRIPE_CLIENT",
      }),
    );

  const subscription = (
    organizationId: string,
  ): AsyncResult<SubscriptionItem> =>
    call(
      "billing_subscription_item",
      { tenant: organizationId },
      subscriptionItemOf,
    ).andThen((found) =>
      Promise.resolve(
        found === undefined
          ? err(
              dbError("not_found", "This tenant has no active subscription", {
                hint: "BILLING_NO_SUBSCRIPTION",
              }),
            )
          : ok(found),
      ),
    );

  const rows = (value: unknown): readonly StripeRow[] =>
    Array.isArray(value) ? value.filter(isRecord) : [];

  const invoices = (
    organizationId: string,
    list: { readonly limit?: number } = {},
  ): AsyncResult<readonly StripeRow[]> =>
    call(
      "billing_invoices",
      { tenant: organizationId, max_rows: list.limit ?? 50 },
      rows,
    );

  const ownInvoice = (
    organizationId: string,
    invoiceId: string,
  ): AsyncResult<string> =>
    invoices(organizationId, { limit: 500 }).andThen((list) =>
      Promise.resolve(
        list.some((row) => row["id"] === invoiceId)
          ? ok(invoiceId)
          : err(
              dbError("not_found", "This tenant has no such invoice", {
                hint: "BILLING_INVOICE_NOT_FOUND",
              }),
            ),
      ),
    );

  return {
    customer,
    ensureCustomer,
    changePlan: (organizationId, change) =>
      priceOf(change).andThen((price) =>
        subscription(organizationId).andThen(async (found) => {
          const updated = await withStripe(async (client) =>
            client.subscriptions.update?.(
              found.subscriptionId,
              {
                items: [{ id: found.itemId, price }],
                proration_behavior:
                  change.prorationBehavior ?? "create_prorations",
                ...(change.resume === false
                  ? {}
                  : { cancel_at_period_end: false }),
              },
              change.idempotencyKey === undefined
                ? undefined
                : { idempotencyKey: change.idempotencyKey },
            ),
          );
          if (!updated.ok) return updated;
          if (updated.data === undefined)
            return missing("subscriptions.update");
          emit("billing.subscription_updated", {
            organizationId,
            subscriptionId: found.subscriptionId,
          });
          return ok({ ...found, price });
        }),
      ),
    cancelAtPeriodEnd: (organizationId, cancel) =>
      subscription(organizationId).andThen(async (found) => {
        const updated = await withStripe(async (client) =>
          client.subscriptions.update?.(found.subscriptionId, {
            cancel_at_period_end: cancel,
          }),
        );
        if (!updated.ok) return updated;
        return updated.data === undefined
          ? missing("subscriptions.update")
          : ok(updated.data.id);
      }),
    invoices,
    paymentMethods: (organizationId) =>
      call("billing_payment_methods", { tenant: organizationId }, rows),
    voidInvoice: (organizationId, invoiceId) =>
      ownInvoice(organizationId, invoiceId).andThen(async () => {
        const voided = await withStripe(async (client) =>
          client.invoices?.voidInvoice(invoiceId),
        );
        if (!voided.ok) return voided;
        return voided.data === undefined
          ? missing("invoices.voidInvoice")
          : ok(voided.data.id);
      }),
    markInvoiceUncollectible: (organizationId, invoiceId) =>
      ownInvoice(organizationId, invoiceId).andThen(async () => {
        const marked = await withStripe(async (client) =>
          client.invoices?.markUncollectible(invoiceId),
        );
        if (!marked.ok) return marked;
        return marked.data === undefined
          ? missing("invoices.markUncollectible")
          : ok(marked.data.id);
      }),
    customerDetails: (organizationId) =>
      call("billing_customer_details", { tenant: organizationId }, (value) =>
        isRecord(value) ? value : undefined,
      ),
    updateCustomer: (organizationId, update) =>
      ensureCustomer(organizationId).andThen(async (customerId) => {
        const updated = await withStripe(async (client) =>
          client.customers.update?.(customerId, {
            ...(update.email === undefined ? {} : { email: update.email }),
            ...(update.name === undefined ? {} : { name: update.name }),
            ...(update.phone === undefined ? {} : { phone: update.phone }),
            ...(update.address === undefined
              ? {}
              : { address: update.address }),
            ...update.params,
          }),
        );
        if (!updated.ok) return updated;
        return updated.data === undefined
          ? missing("customers.update")
          : ok(updated.data.id);
      }),
    checkout: (organizationId, checkout) =>
      priceOf(checkout).andThen((price) =>
        ensureCustomer(organizationId, checkout).andThen(async (customerId) => {
          const quantity =
            checkout.quantity === "seats"
              ? await seats(organizationId)
              : ok(checkout.quantity ?? 1);
          if (!quantity.ok) return quantity;
          const mode = checkout.mode ?? "subscription";
          return withStripe(async (client) => {
            const session = await client.checkout.sessions.create(
              {
                customer: customerId,
                mode,
                client_reference_id: organizationId,
                line_items: [{ price, quantity: quantity.data }],
                success_url: checkout.successUrl,
                ...(checkout.cancelUrl === undefined
                  ? {}
                  : { cancel_url: checkout.cancelUrl }),
                metadata: { [ORGANIZATION_KEY]: organizationId },
                ...(mode === "subscription"
                  ? {
                      subscription_data: {
                        metadata: { [ORGANIZATION_KEY]: organizationId },
                      },
                    }
                  : {}),
                ...checkout.params,
              },
              checkout.idempotencyKey === undefined
                ? undefined
                : { idempotencyKey: checkout.idempotencyKey },
            );
            return { id: session.id, url: session.url ?? undefined };
          });
        }),
      ),
    portal: (organizationId, portal) =>
      customer(organizationId).andThen(async (customerId) => {
        if (customerId === undefined) {
          return err(
            dbError("not_found", "This tenant has no Stripe customer yet", {
              hint: "BILLING_NO_CUSTOMER",
            }),
          );
        }
        return withStripe(async (client) => {
          const session = await client.billingPortal.sessions.create({
            customer: customerId,
            return_url: portal.returnUrl,
          });
          return { url: session.url };
        });
      }),
    status: (organizationId) =>
      call("billing_status", { tenant: organizationId }, (value) => {
        const row = recordOf(value, "billing_status");
        return {
          customerId: optionalText(row["customer"]),
          seats: Number(row["seats"] ?? 0),
          subscription: subscriptionItemOf(row["subscription"]),
        };
      }),
    syncSeats,
    cancelSubscription: (organizationId) =>
      item(organizationId).andThen(async (found) => {
        if (found === undefined) return ok(undefined);
        const cancelled = await withStripe((client) =>
          client.subscriptions.cancel(found.subscriptionId),
        );
        return cancelled.ok ? ok(cancelled.data.id) : cancelled;
      }),
    seatSink: () => ({
      async send(events) {
        const latest = new Map<string, string>();
        for (const event of events) {
          const tenant = optionalText(event["partitionkey"]);
          if (tenant !== undefined && SEAT_EVENT.test(event.type)) {
            latest.set(tenant, event.id);
          }
        }
        for (const [tenant, id] of latest) {
          await syncSeats(tenant, { key: id }).orThrow();
        }
      },
    }),
    handleStripeEvent,
  };
}
