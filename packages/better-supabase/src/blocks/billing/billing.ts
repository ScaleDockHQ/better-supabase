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
  readonly price: string;
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

  return {
    customer,
    ensureCustomer,
    checkout: (organizationId, checkout) =>
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
              line_items: [{ price: checkout.price, quantity: quantity.data }],
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
