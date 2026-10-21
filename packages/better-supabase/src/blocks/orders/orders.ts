import type { Money } from "../../commerce/money.ts";
import type {
  Payment,
  PaymentEvent,
  PaymentProvider,
} from "../../commerce/payments.ts";
import type {
  TaxCart,
  TaxProvider,
  TaxTransaction,
} from "../../commerce/tax.ts";
import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { DbError } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { WebhookInput } from "../../core/signatures.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { JobHandler } from "../jobs/types.ts";
import type { BlockOptions } from "../shared.ts";
import type {
  Address,
  CartLine,
  Order,
  OrderRefundStatus,
  OrderStatus,
  PricedCart,
  QuantityLine,
  ShippingOption,
} from "./codecs.ts";

import { money } from "../../commerce/money.ts";
import { paymentProviderOf } from "../../commerce/payments.ts";
import { taxProviderOf } from "../../commerce/tax.ts";
import { blockFields, readFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  nullableText,
  recordOf,
  textOf,
} from "../shared.ts";
import {
  amountText,
  moneyOf,
  orderOf,
  ORDER_STATUSES,
  pricedCartOf,
  quoteToJson,
  REFUND_STATUSES,
  refundedTaxLines,
  shippingOptionsOf,
  transactionToJson,
} from "./codecs.ts";

export interface OrdersOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the extra columns of the orders table
   * (`blocks.orders.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  /** Takes the payment at checkout and the money back on refunds. */
  readonly payments?: PaymentProvider;
  /** Quotes tax at checkout and records the sale once the order is paid. */
  readonly tax?: TaxProvider;
  /**
   * The tax category of each cart line, such as `standard` or a provider tax
   * code.
   */
  readonly taxCategory?: string | ((line: CartLine) => string | undefined);
  /** The tax category of the shipping line. */
  readonly shippingTaxCategory?: string;
  /** Prices already contain the tax (prices shown with VAT). Default `false`. */
  readonly pricesIncludeTax?: boolean;
  /** `manual` holds the funds until `capture`. Default `automatic`. */
  readonly capture?: "automatic" | "manual";
  /** `withBlockHooks` hooks around any orders method. */
  readonly hooks?: NoInfer<BlockHooks<Orders<FieldsOf<S>>>>;
  /**
   * Receives the errors `after` hooks throw and failed tax calls. Default:
   * `console`.
   */
  readonly logger?: Logger;
}

export interface ShippingRateInput {
  /** Updates this rate; creates one when left out. */
  readonly id?: string;
  readonly name: string;
  /** ISO 3166-1 alpha-2 codes; empty ships everywhere. */
  readonly countries?: readonly string[];
  /** `weight` adds `amountPerKg` for each started kilogram. Default `flat`. */
  readonly kind?: "flat" | "weight";
  readonly amount: Money;
  readonly amountPerKg?: Money;
  /** Free once the discounted subtotal reaches it. */
  readonly freeOver?: Money;
  readonly active?: boolean;
}

export interface CartInput {
  /** ISO 4217; the catalog prices the cart in it. */
  readonly currency: string;
  readonly priceListId?: string;
  readonly email?: string;
}

export interface CartDetails {
  readonly email?: string;
  readonly shippingAddress?: Address;
  readonly billingAddress?: Address;
}

export interface CheckoutInput<F extends object = Record<never, never>> {
  /** Reserve stock at this location instead of the one with the most. */
  readonly locationId?: string;
  /** The payment provider's customer id. */
  readonly customer?: string;
  /** Where a redirecting payment method returns the customer. */
  readonly returnUrl?: string;
  readonly metadata?: Readonly<Record<string, string>>;
  /** Values for the order's extra columns (`options.extraColumns`). */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface Checkout<F extends object = Record<never, never>> {
  readonly order: Order<F>;
  /**
   * The payment to confirm in the browser (its `clientSecret` or
   * `redirectUrl`). Null for a free order or without a payments provider.
   */
  readonly payment: Payment | null;
}

export interface PaymentRecord {
  readonly orderId: string;
  readonly status: OrderStatus;
  readonly paidTotal: Money;
  /** This payment paid the order. */
  readonly newlyPaid: boolean;
  readonly invoiceNumber: string | null;
}

export interface FulfillmentInput {
  /** Default: every unit not fulfilled yet. */
  readonly lines?: readonly QuantityLine[];
  readonly locationId?: string;
  readonly carrier?: string;
  readonly trackingNumber?: string;
  readonly trackingUrl?: string;
}

export interface TrackingInput {
  readonly carrier?: string;
  readonly trackingNumber?: string;
  readonly trackingUrl?: string;
}

export interface RefundRequest {
  /** Default: what is paid and not refunded yet. */
  readonly amount?: Money;
  readonly returnId?: string;
  readonly reason?: string;
}

export interface RefundOutcome {
  readonly id: string;
  readonly orderId: string;
  readonly amount: Money;
  readonly status: OrderRefundStatus;
  readonly orderStatus: OrderStatus;
  readonly refundedTotal: Money;
  /** The tax provider's reversal; null without one or when it failed (logged). */
  readonly taxReversal: TaxTransaction | null;
}

/** What `webhook` and `handlePaymentEvent` did with an event. */
export type PaymentEventOutcome =
  | {
      readonly event: string;
      readonly kind: "payment";
      readonly record: PaymentRecord;
    }
  | {
      readonly event: string;
      readonly kind: "refund";
      readonly refund: RefundOutcome;
    }
  | {
      readonly event: string;
      readonly kind: "ignored";
      readonly reason: string;
    };

export interface Invoice<F extends object = Record<never, never>> {
  readonly number: string;
  readonly issuedAt: Temporal.Instant;
  readonly order: Order<F>;
}

export interface Orders<F extends object = Record<never, never>> {
  saveShippingRate(
    organizationId: string,
    input: ShippingRateInput,
  ): AsyncResult<{ readonly id: string }>;
  deleteShippingRate(rateId: string): AsyncResult<boolean>;
  /**
   * The caller's open cart in the organization and currency, created when there
   * is none.
   */
  createCart(
    organizationId: string,
    input: CartInput,
  ): AsyncResult<{ readonly id: string; readonly currency: string }>;
  /** Adds `quantity` to the variant's line. */
  addToCart(
    cartId: string,
    variantId: string,
    quantity: number,
  ): AsyncResult<{ readonly lineId: string; readonly quantity: number }>;
  /** Sets the variant's quantity; zero removes the line. */
  setCartLine(
    cartId: string,
    variantId: string,
    quantity: number,
  ): AsyncResult<{ readonly lineId: string | null; readonly quantity: number }>;
  setCartDetails(cartId: string, details: CartDetails): AsyncResult<boolean>;
  setShippingRate(cartId: string, rateId: string): AsyncResult<boolean>;
  /** The rates that ship to the cart's address, with their amount for this cart. */
  shippingOptions(cartId: string): AsyncResult<readonly ShippingOption[]>;
  /** The cart at today's prices, with what keeps it from checkout. */
  priceCart(cartId: string): AsyncResult<PricedCart>;
  /**
   * Moves an anonymous user's open carts to the user they signed in as. Service
   * only. Resolves to the number of carts moved or merged.
   */
  mergeCarts(fromUserId: string, toUserId: string): AsyncResult<number>;
  /**
   * Prices the cart, quotes tax, places the order (reserving its stock) and
   * creates the payment. Repeating it for the same cart returns the same order
   * and, through the idempotency key, the same payment.
   */
  checkout(cartId: string, input?: CheckoutInput<F>): AsyncResult<Checkout<F>>;
  /**
   * Stores a payment's state on its order; the order is paid once its total is
   * captured. Service only.
   */
  recordPayment(
    orderId: string | null,
    payment: Payment,
  ): AsyncResult<PaymentRecord>;
  /** Captures the order's authorized payments. */
  capture(orderId: string): AsyncResult<Order<F>>;
  /** Applies one provider event: a payment update or a refund's outcome. */
  handlePaymentEvent(event: PaymentEvent): AsyncResult<PaymentEventOutcome>;
  /** Verifies a provider webhook and applies its events. */
  webhook(input: WebhookInput): AsyncResult<readonly PaymentEventOutcome[]>;
  /**
   * Records the paid order's sale with the tax provider; retries a failed
   * commit.
   */
  commitTax(orderId: string): AsyncResult<TaxTransaction | null>;
  /** Cancels an unpaid order, releasing its stock and its open payments. */
  cancelOrder(orderId: string, reason?: string): AsyncResult<boolean>;
  /** Cancels orders whose payment window passed. Service only. */
  expireOrders(maxRows?: number): AsyncResult<number>;
  getOrder(orderId: string): AsyncResult<Order<F>>;
  createFulfillment(
    orderId: string,
    input?: FulfillmentInput,
  ): AsyncResult<{ readonly id: string }>;
  shipFulfillment(
    fulfillmentId: string,
    tracking?: TrackingInput,
  ): AsyncResult<boolean>;
  deliverFulfillment(fulfillmentId: string): AsyncResult<boolean>;
  /** Cancels a fulfillment that hasn't shipped. */
  cancelFulfillment(fulfillmentId: string): AsyncResult<boolean>;
  requestReturn(
    orderId: string,
    lines: readonly QuantityLine[],
    reason?: string,
  ): AsyncResult<{ readonly id: string; readonly quantity: number }>;
  /**
   * Receives the returned units; `restock` (default true) puts tracked ones
   * back in stock.
   */
  receiveReturn(
    returnId: string,
    options?: { readonly restock?: boolean; readonly locationId?: string },
  ): AsyncResult<boolean>;
  rejectReturn(returnId: string): AsyncResult<boolean>;
  /**
   * Refunds through the payment provider and reverses the refunded part of the
   * tax.
   */
  refund(orderId: string, input?: RefundRequest): AsyncResult<RefundOutcome>;
  /** The invoice of a paid order. */
  invoice(orderId: string): AsyncResult<Invoice<F>>;
  /** The handler for a scheduled job that runs `expireOrders`. */
  readonly job: JobHandler<unknown>;
}

const isTrue = (value: unknown): boolean => value === true;

const failure = (hint: string, message: string): DbError =>
  dbError("invalid_request", message, { hint });

function maxRowsOf(payload: unknown): number | undefined {
  if (!isRecord(payload)) {
    return undefined;
  }

  const value = payload["maxRows"];

  return typeof value === "number" ? value : undefined;
}

function paymentRecordOf(value: unknown, currency: string): PaymentRecord {
  const row = recordOf(value, "record_payment");

  return {
    orderId: textOf(row["orderId"]),
    status: enumOrThrow(row["status"], ORDER_STATUSES, "order status"),
    paidTotal: moneyOf(row["paidTotal"], currency),
    newlyPaid: row["newlyPaid"] === true,
    invoiceNumber: nullableText(row["invoiceNumber"]),
  };
}

const PAYMENT_EVENT_STATUS = {
  "payment.requires_action": "requires_action",
  "payment.processing": "processing",
  "payment.authorized": "authorized",
  "payment.succeeded": "succeeded",
  "payment.failed": "failed",
  "payment.canceled": "canceled",
} as const satisfies Record<string, Payment["status"]>;

function refundStatusOf(
  status: "pending" | "succeeded" | "failed" | "canceled",
): OrderRefundStatus {
  return status === "canceled" ? "failed" : status;
}

/**
 * Carts, checkout, payments, fulfillments, returns, refunds and invoices over
 * the `orders` SQL module.
 */
export function createOrders<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: OrdersOptions<S>): Orders<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const fields: BlockFields<F> = blockFields(options.fields, "order fields");

  const parsed = (result: AsyncResult<Order>): AsyncResult<Order<F>> =>
    result.andThen((order) => readFields(fields, order));

  const payments = options.payments
    ? paymentProviderOf(options.payments)
    : undefined;

  const tax = options.tax ? taxProviderOf(options.tax) : undefined;
  const logger = options.logger ?? console;
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const categoryOf = (line: CartLine): string | undefined =>
    typeof options.taxCategory === "function"
      ? options.taxCategory(line)
      : options.taxCategory;

  const loadOrder = (orderId: string): AsyncResult<Order<F>> =>
    parsed(service("get_order", { order_id: orderId }, orderOf));

  const recordPayment: Orders["recordPayment"] = (orderId, payment) =>
    service(
      "record_payment",
      {
        order_id: orderId,
        provider: payment.provider,
        reference: payment.id,
        status: payment.status,
        currency: payment.amount.currency,
        amount: amountText(payment.amount),
        captured: amountText(payment.captured),
        refunded: amountText(payment.refunded),
      },
      (value) => paymentRecordOf(value, payment.amount.currency),
    );

  const commitTax: Orders["commitTax"] = (orderId) =>
    AsyncResult.from(async (): Promise<Result<TaxTransaction | null>> => {
      if (!tax) {
        return ok(null);
      }

      const order = await loadOrder(orderId);

      if (!order.ok) {
        return order;
      }

      const { taxQuote, taxTransaction } = order.data;

      if (taxTransaction) {
        return ok(taxTransaction);
      }

      if (!taxQuote || order.data.invoiceNumber === null) {
        return ok(null);
      }

      const committed = await tax.commit(
        { quote: taxQuote, reference: order.data.number },
        { idempotencyKey: `tax:${orderId}` },
      );

      if (!committed.ok) {
        return committed;
      }

      const stored = await service(
        "set_order_tax_transaction",
        {
          order_id: orderId,
          tax_transaction: transactionToJson(committed.data),
        },
        isTrue,
      );

      return stored.ok ? ok(committed.data) : stored;
    });

  /**
   * Commits the tax once a payment paid the order; a failure is logged and
   * retried with `commitTax`.
   */
  const afterPayment = async (record: PaymentRecord): Promise<void> => {
    if (!record.newlyPaid) {
      return;
    }

    const committed = await commitTax(record.orderId);

    if (!committed.ok) {
      logger.warn("orders: tax commit failed; retry with commitTax", {
        orderId: record.orderId,
        error: committed.error,
      });
    }
  };

  const record = (
    orderId: string | null,
    payment: Payment,
  ): AsyncResult<PaymentRecord> =>
    recordPayment(orderId, payment).andThen(async (result) => {
      await afterPayment(result);

      return ok(result);
    });

  const taxCartOf = (cart: PricedCart, address: Address): TaxCart => {
    const inclusive = options.pricesIncludeTax === true;

    return {
      currency: cart.currency,
      lines: cart.lines.map((line) => {
        const category = categoryOf(line);

        return {
          id: line.id,
          amount: line.total,
          quantity: line.quantity,
          ...(category === undefined ? {} : { taxCategory: category }),
          ...(inclusive ? { inclusive } : {}),
        };
      }),
      ...(cart.shippingTotal.amount > 0n
        ? {
            shipping: {
              amount: cart.shippingTotal,
              ...(options.shippingTaxCategory === undefined
                ? {}
                : { taxCategory: options.shippingTaxCategory }),
              ...(inclusive ? { inclusive } : {}),
            },
          }
        : {}),
      address: {
        country: address.country,
        ...(address.state === undefined ? {} : { state: address.state }),
        ...(address.postalCode === undefined
          ? {}
          : { postalCode: address.postalCode }),
        ...(address.city === undefined ? {} : { city: address.city }),
        ...(address.line1 === undefined ? {} : { line1: address.line1 }),
        ...(address.line2 === undefined ? {} : { line2: address.line2 }),
      },
      reference: cart.id,
    };
  };

  const checkout: Orders<F>["checkout"] = (cartId, input = {}) =>
    AsyncResult.from(async (): Promise<Result<Checkout<F>>> => {
      const checked =
        input.fields === undefined
          ? ok(undefined)
          : await fields.write({ ...input.fields });

      if (!checked.ok) {
        return checked;
      }

      const priced = await call("price_cart", { cart: cartId }, pricedCartOf);

      if (!priced.ok) {
        return priced;
      }

      const cart = priced.data;

      if (cart.status === "open") {
        if (cart.lines.length === 0) {
          return err(failure("ORDERS_CART_EMPTY", "the cart has no lines"));
        }

        if (cart.problems.length > 0) {
          return err(
            failure(
              "ORDERS_CART_INVALID",
              `the cart can't check out: ${cart.problems.map((problem) => problem.problem).join(", ")}`,
            ),
          );
        }
      }

      let quote: Record<string, unknown> | null = null;

      if (tax && cart.status === "open") {
        const address = cart.shippingAddress ?? cart.billingAddress;

        if (!address) {
          return err(
            failure(
              "ORDERS_ADDRESS_REQUIRED",
              "tax needs a shipping or billing address on the cart",
            ),
          );
        }

        const quoted = await tax.quote(taxCartOf(cart, address));

        if (!quoted.ok) {
          return quoted;
        }

        quote = quoteToJson(quoted.data);
      }

      const placed = await parsed(
        service(
          "place_order",
          {
            cart: cartId,
            tax: quote,
            expected_total: amountText(cart.total),
            location: input.locationId ?? null,
            fields: checked.data,
          },
          orderOf,
        ),
      );

      if (!placed.ok) {
        return placed;
      }

      const order = placed.data;

      if (order.status !== "pending_payment") {
        return ok({ order, payment: null });
      }

      if (order.total.amount === 0n) {
        const zero = money(0, order.currency);

        const free = await record(order.id, {
          id: `free:${order.id}`,
          provider: "none",
          status: "succeeded",
          amount: zero,
          captured: zero,
          refunded: zero,
          reference: order.id,
          metadata: {},
        });

        if (!free.ok) {
          return free;
        }

        const paid = await loadOrder(order.id);

        return paid.ok ? ok({ order: paid.data, payment: null }) : paid;
      }

      if (!payments) {
        return ok({ order, payment: null });
      }

      const created = await payments.createPayment(
        {
          amount: order.total,
          reference: order.id,
          capture: options.capture ?? "automatic",
          ...(input.customer === undefined ? {} : { customer: input.customer }),
          description: `Order ${order.number}`,
          ...(input.returnUrl === undefined
            ? {}
            : { returnUrl: input.returnUrl }),
          metadata: {
            ...input.metadata,
            orderId: order.id,
            orderNumber: order.number,
          },
        },
        { idempotencyKey: `order:${order.id}:payment` },
      );

      if (!created.ok) {
        return created;
      }

      const stored = await record(order.id, created.data);

      if (!stored.ok) {
        return stored;
      }

      const current = await loadOrder(order.id);

      return current.ok
        ? ok({ order: current.data, payment: created.data })
        : current;
    });

  const capture: Orders<F>["capture"] = (orderId) =>
    AsyncResult.from(async (): Promise<Result<Order<F>>> => {
      if (!payments) {
        return err(
          failure("ORDERS_NO_PAYMENTS", "capture needs a payments provider"),
        );
      }

      const order = await loadOrder(orderId);

      if (!order.ok) {
        return order;
      }

      for (const payment of order.data.payments) {
        if (
          payment.status !== "authorized" ||
          payment.provider !== payments.name
        ) {
          continue;
        }

        const captured = await payments.capture(
          payment.reference,
          {},
          { idempotencyKey: `capture:${payment.id}` },
        );

        if (!captured.ok) {
          return captured;
        }

        const stored = await record(orderId, captured.data);

        if (!stored.ok) {
          return stored;
        }
      }

      return loadOrder(orderId);
    });

  const completeRefund = (
    refundId: string | null,
    status: OrderRefundStatus,
    providerReference: string | null,
  ): AsyncResult<Omit<RefundOutcome, "taxReversal">> =>
    service(
      "complete_refund",
      { refund: refundId, status, provider_reference: providerReference },
      (value) => recordOf(value, "complete_refund"),
    ).andThen(async (row) => {
      const order = await loadOrder(textOf(row["orderId"]));

      if (!order.ok) {
        return order;
      }

      const { currency } = order.data;

      return ok({
        id: textOf(row["id"]),
        orderId: order.data.id,
        amount: moneyOf(row["amount"], currency),
        status: enumOrThrow(row["status"], REFUND_STATUSES, "refund status"),
        orderStatus: enumOrThrow(
          row["orderStatus"],
          ORDER_STATUSES,
          "order status",
        ),
        refundedTotal: moneyOf(row["refundedTotal"], currency),
      });
    });

  const reverseTax = async (
    outcome: Omit<RefundOutcome, "taxReversal">,
  ): Promise<RefundOutcome> => {
    if (!tax || outcome.status !== "succeeded") {
      return { ...outcome, taxReversal: null };
    }

    const order = await loadOrder(outcome.orderId);
    const transaction = order.ok ? order.data.taxTransaction : undefined;

    if (!order.ok || !transaction) {
      return { ...outcome, taxReversal: null };
    }

    const whole = outcome.amount.amount >= order.data.total.amount;

    const reversed = await tax.reverse(
      {
        transaction,
        reference: outcome.id,
        ...(whole
          ? {}
          : {
              lines: refundedTaxLines(
                transaction,
                outcome.amount,
                order.data.total,
              ),
            }),
      },
      { idempotencyKey: `tax-reverse:${outcome.id}` },
    );

    if (reversed.ok) {
      return { ...outcome, taxReversal: reversed.data };
    }

    logger.warn("orders: tax reversal failed", {
      refundId: outcome.id,
      error: reversed.error,
    });

    return { ...outcome, taxReversal: null };
  };

  const refund: Orders["refund"] = (orderId, input = {}) =>
    AsyncResult.from(async (): Promise<Result<RefundOutcome>> => {
      if (!payments) {
        return err(
          failure("ORDERS_NO_PAYMENTS", "refunds need a payments provider"),
        );
      }

      const created = await call(
        "create_refund",
        {
          order_id: orderId,
          amount: input.amount === undefined ? null : amountText(input.amount),
          return_id: input.returnId ?? null,
          reason: input.reason ?? null,
        },
        (value) => recordOf(value, "create_refund"),
      );

      if (!created.ok) {
        return created;
      }

      const row = created.data;
      const refundId = textOf(row["id"]);
      const amount = moneyOf(row["amount"], textOf(row["currency"]));

      const providerRefund = await payments.refund(
        textOf(row["paymentReference"]),
        {
          amount,
          ...(input.reason === undefined ? {} : { reason: input.reason }),
        },
        { idempotencyKey: `refund:${refundId}` },
      );

      if (!providerRefund.ok) {
        await completeRefund(refundId, "failed", null);

        return providerRefund;
      }

      const completed = await completeRefund(
        refundId,
        refundStatusOf(providerRefund.data.status),
        providerRefund.data.id,
      );

      if (!completed.ok) {
        return completed;
      }

      return ok(await reverseTax(completed.data));
    });

  const handlePaymentEvent: Orders["handlePaymentEvent"] = (event) =>
    AsyncResult.from(async (): Promise<Result<PaymentEventOutcome>> => {
      if (event.type === "refund.succeeded" || event.type === "refund.failed") {
        if (event.refundId === undefined) {
          return ok({
            event: event.id,
            kind: "ignored",
            reason: "no refund id",
          });
        }

        const completed = await completeRefund(
          null,
          event.type === "refund.succeeded" ? "succeeded" : "failed",
          event.refundId,
        );

        if (!completed.ok) {
          if (completed.error.hint === "ORDERS_REFUND_NOT_FOUND") {
            return ok({
              event: event.id,
              kind: "ignored",
              reason: "unknown refund",
            });
          }

          return completed;
        }

        return ok({
          event: event.id,
          kind: "refund",
          refund: await reverseTax(completed.data),
        });
      }

      let payment: Payment;

      if (payments?.get) {
        const fetched = await payments.get(event.paymentId);

        if (!fetched.ok) {
          return fetched;
        }

        payment = fetched.data;
      } else {
        if (event.amount === undefined) {
          return ok({ event: event.id, kind: "ignored", reason: "no amount" });
        }

        const status = PAYMENT_EVENT_STATUS[event.type];
        const zero = money(0, event.amount.currency);
        payment = {
          id: event.paymentId,
          provider: payments?.name ?? "unknown",
          status,
          amount: event.amount,
          captured: status === "succeeded" ? event.amount : zero,
          refunded: zero,
          reference: event.reference ?? "",
          metadata: {},
        };
      }

      const orderId =
        payment.reference === ""
          ? (event.reference ?? null)
          : payment.reference;

      const stored = await record(orderId, payment);

      if (!stored.ok) {
        if (stored.error.hint === "ORDERS_ORDER_NOT_FOUND") {
          return ok({
            event: event.id,
            kind: "ignored",
            reason: "unknown order",
          });
        }

        return stored;
      }

      return ok({ event: event.id, kind: "payment", record: stored.data });
    });

  const webhook: Orders["webhook"] = (input) =>
    AsyncResult.from(
      async (): Promise<Result<readonly PaymentEventOutcome[]>> => {
        if (!payments) {
          return err(
            failure("ORDERS_NO_PAYMENTS", "webhooks need a payments provider"),
          );
        }

        const parsed = await payments.parseWebhook(input);

        if (!parsed.ok) {
          return parsed;
        }

        const outcomes: PaymentEventOutcome[] = [];

        for (const event of parsed.data) {
          const outcome = await handlePaymentEvent(event);

          if (!outcome.ok) {
            return outcome;
          }

          outcomes.push(outcome.data);
        }

        return ok(outcomes);
      },
    );

  const cancelOrder: Orders["cancelOrder"] = (orderId, reason) =>
    call(
      "cancel_order",
      { order_id: orderId, reason: reason ?? null },
      isTrue,
    ).andThen(async (cancelled) => {
      if (!cancelled || !payments?.cancel) {
        return ok(cancelled);
      }

      const order = await loadOrder(orderId);

      if (!order.ok) {
        return ok(cancelled);
      }

      for (const payment of order.data.payments) {
        if (
          payment.provider !== payments.name ||
          !["requires_action", "processing", "authorized"].includes(
            payment.status,
          )
        ) {
          continue;
        }

        const released = await payments.cancel(payment.reference, {
          idempotencyKey: `cancel:${payment.id}`,
        });

        if (released.ok) {
          await recordPayment(orderId, released.data);
        } else {
          logger.warn("orders: cancelling the payment failed", {
            orderId,
            paymentId: payment.reference,
            error: released.error,
          });
        }
      }

      return ok(cancelled);
    });

  const expireOrders: Orders["expireOrders"] = (maxRows) =>
    service("expire_orders", { max_rows: maxRows ?? null }, Number);

  const orders: Orders<F> = {
    saveShippingRate: (organizationId, input) =>
      call(
        "save_shipping_rate",
        {
          tenant: organizationId,
          rate: input.id ?? null,
          data: {
            name: input.name,
            countries: input.countries ?? [],
            kind: input.kind ?? "flat",
            currency: input.amount.currency,
            amount: amountText(input.amount),
            ...(input.amountPerKg === undefined
              ? {}
              : { amountPerKg: amountText(input.amountPerKg) }),
            ...(input.freeOver === undefined
              ? {}
              : { freeOver: amountText(input.freeOver) }),
            active: input.active ?? true,
          },
        },
        (value) => ({
          id: textOf(recordOf(value, "save_shipping_rate")["id"]),
        }),
      ),
    deleteShippingRate: (rateId) =>
      call("delete_shipping_rate", { rate: rateId }, isTrue),
    createCart: (organizationId, input) =>
      call(
        "create_cart",
        {
          tenant: organizationId,
          currency: input.currency,
          price_list: input.priceListId ?? null,
          email: input.email ?? null,
        },
        (value) => {
          const row = recordOf(value, "create_cart");

          return { id: textOf(row["id"]), currency: textOf(row["currency"]) };
        },
      ),
    addToCart: (cartId, variantId, quantity) =>
      call(
        "add_to_cart",
        { cart: cartId, variant: variantId, quantity },
        (value) => {
          const row = recordOf(value, "add_to_cart");

          return {
            lineId: textOf(row["lineId"]),
            quantity: Number(row["quantity"]),
          };
        },
      ),
    setCartLine: (cartId, variantId, quantity) =>
      call(
        "set_cart_line",
        { cart: cartId, variant: variantId, quantity },
        (value) => {
          const row = recordOf(value, "set_cart_line");

          return {
            lineId: nullableText(row["lineId"]),
            quantity: Number(row["quantity"]),
          };
        },
      ),
    setCartDetails: (cartId, details) =>
      call(
        "set_cart_details",
        {
          cart: cartId,
          email: details.email ?? null,
          shipping_address: details.shippingAddress ?? null,
          billing_address: details.billingAddress ?? null,
        },
        isTrue,
      ),
    setShippingRate: (cartId, rateId) =>
      call("set_cart_shipping_rate", { cart: cartId, rate: rateId }, isTrue),
    shippingOptions: (cartId) =>
      call("shipping_options", { cart: cartId }, shippingOptionsOf),
    priceCart: (cartId) => call("price_cart", { cart: cartId }, pricedCartOf),
    mergeCarts: (fromUserId, toUserId) =>
      service(
        "merge_carts",
        { from_user: fromUserId, to_user: toUserId },
        Number,
      ),
    checkout,
    recordPayment,
    capture,
    handlePaymentEvent,
    webhook,
    commitTax,
    cancelOrder,
    expireOrders,
    getOrder: (orderId) =>
      parsed(call("get_order", { order_id: orderId }, orderOf)),
    createFulfillment: (orderId, input = {}) =>
      call(
        "create_fulfillment",
        {
          order_id: orderId,
          lines: input.lines
            ? input.lines.map((line) => ({
                lineId: line.lineId,
                quantity: line.quantity,
              }))
            : null,
          location: input.locationId ?? null,
          carrier: input.carrier ?? null,
          tracking_number: input.trackingNumber ?? null,
          tracking_url: input.trackingUrl ?? null,
        },
        (value) => ({
          id: textOf(recordOf(value, "create_fulfillment")["id"]),
        }),
      ),
    shipFulfillment: (fulfillmentId, tracking = {}) =>
      call(
        "ship_fulfillment",
        {
          fulfillment: fulfillmentId,
          carrier: tracking.carrier ?? null,
          tracking_number: tracking.trackingNumber ?? null,
          tracking_url: tracking.trackingUrl ?? null,
        },
        isTrue,
      ),
    deliverFulfillment: (fulfillmentId) =>
      call("deliver_fulfillment", { fulfillment: fulfillmentId }, isTrue),
    cancelFulfillment: (fulfillmentId) =>
      call("cancel_fulfillment", { fulfillment: fulfillmentId }, isTrue),
    requestReturn: (orderId, lines, reason) =>
      call(
        "request_return",
        {
          order_id: orderId,
          lines: lines.map((line) => ({
            lineId: line.lineId,
            quantity: line.quantity,
          })),
          reason: reason ?? null,
        },
        (value) => {
          const row = recordOf(value, "request_return");

          return { id: textOf(row["id"]), quantity: Number(row["quantity"]) };
        },
      ),
    receiveReturn: (returnId, receive = {}) =>
      call(
        "receive_return",
        {
          return_id: returnId,
          restock: receive.restock ?? true,
          location: receive.locationId ?? null,
        },
        isTrue,
      ),
    rejectReturn: (returnId) =>
      call("reject_return", { return_id: returnId }, isTrue),
    refund,
    invoice: (orderId) =>
      parsed(call("get_order", { order_id: orderId }, orderOf)).andThen(
        (order) =>
          Promise.resolve(
            order.invoiceNumber === null || order.invoicedAt === undefined
              ? err(failure("ORDERS_NOT_INVOICED", "the order isn't paid yet"))
              : ok({
                  number: order.invoiceNumber,
                  issuedAt: order.invoicedAt,
                  order,
                }),
          ),
      ),
    job: async (payload) => {
      await expireOrders(maxRowsOf(payload)).orThrow();
    },
  };

  return withBlockHooks(orders, options.hooks, {
    block: "orders",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
