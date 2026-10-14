import type { Payment } from "../commerce/payments.ts";

import { money, type Money } from "../commerce/money.ts";
import {
  type TaxLine,
  type TaxQuote,
  type TaxTransaction,
} from "../commerce/tax.ts";
import {
  enumOrThrow,
  isRecord,
  nullableText,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export const ORDER_STATUSES = [
  "pending_payment",
  "paid",
  "fulfilled",
  "completed",
  "cancelled",
  "refunded",
] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export const FULFILLMENT_STATUSES = [
  "pending",
  "shipped",
  "delivered",
  "cancelled",
] as const;
export type FulfillmentStatus = (typeof FULFILLMENT_STATUSES)[number];

export const RETURN_STATUSES = ["requested", "received", "rejected"] as const;
export type ReturnStatus = (typeof RETURN_STATUSES)[number];

export const REFUND_STATUSES = ["pending", "succeeded", "failed"] as const;
export type OrderRefundStatus = (typeof REFUND_STATUSES)[number];

const PAYMENT_STATUSES = [
  "requires_action",
  "processing",
  "authorized",
  "succeeded",
  "failed",
  "canceled",
] as const;

/** A postal address; `country` is ISO 3166-1 alpha-2. */
export interface Address {
  readonly country: string;
  readonly name?: string;
  readonly company?: string;
  readonly line1?: string;
  readonly line2?: string;
  readonly postalCode?: string;
  readonly city?: string;
  /** The state or province code, such as `CA`. */
  readonly state?: string;
  readonly phone?: string;
}

/** Something that keeps a cart from checkout, such as `unpriced` or `shipping_required`. */
export interface CartProblem {
  readonly problem: string;
  readonly lineId?: string;
  readonly variantId?: string;
  readonly code?: string;
  /** For `promotion_unavailable`: the promotion behind the code. */
  readonly promotionId?: string;
  /** For `promotion_unavailable`, such as `expired`, `limit_reached` or `not_combinable`. */
  readonly reason?: string;
}

export interface CartLine {
  readonly id: string;
  readonly variantId: string;
  readonly productId: string;
  readonly sku: string;
  readonly title: string;
  readonly quantity: number;
  readonly unitAmount: Money;
  /** The price when the line was added, when it changed since. */
  readonly previousUnitAmount?: Money;
  readonly subtotal: Money;
  readonly discount: Money;
  /** After discounts, before tax. */
  readonly total: Money;
  readonly requiresShipping: boolean;
}

export const PROMOTION_KINDS = [
  "percentage",
  "fixed",
  "free_shipping",
] as const;

/** A promotion the cart gets, as the `promotions` module reports it. */
export interface AppliedPromotion {
  readonly promotionId: string;
  readonly name: string;
  readonly kind: (typeof PROMOTION_KINDS)[number];
  readonly code?: string;
  /** Zero for free shipping, which shows in the shipping total instead. */
  readonly discount: Money;
  readonly freeShipping: boolean;
}

export interface PricedCart {
  readonly id: string;
  readonly organizationId: string;
  readonly customerId: string;
  readonly status: "open" | "converted" | "abandoned";
  readonly currency: string;
  readonly email?: string;
  readonly shippingAddress?: Address;
  readonly billingAddress?: Address;
  readonly lines: readonly CartLine[];
  readonly subtotal: Money;
  readonly discountTotal: Money;
  readonly shippingTotal: Money;
  /** Subtotal less discounts plus shipping, before tax. */
  readonly total: Money;
  readonly requiresShipping: boolean;
  readonly weightGrams: number;
  readonly shipping?: {
    readonly rateId: string;
    readonly name: string;
    readonly amount: Money;
  };
  readonly promotions: readonly AppliedPromotion[];
  /** Empty when the cart can check out. */
  readonly problems: readonly CartProblem[];
}

export interface ShippingOption {
  readonly id: string;
  readonly name: string;
  readonly kind: "flat" | "weight";
  readonly amount: Money;
}

export interface OrderLine {
  readonly id: string;
  /** Null once the variant is deleted; the line keeps its SKU and title. */
  readonly variantId: string | null;
  readonly productId: string | null;
  readonly sku: string;
  readonly title: string;
  readonly quantity: number;
  readonly unitAmount: Money;
  readonly subtotal: Money;
  readonly discount: Money;
  readonly tax: Money;
  /** After discounts, without tax. */
  readonly total: Money;
  readonly requiresShipping: boolean;
  readonly locationId: string | null;
  readonly reservationId: string | null;
  readonly fulfilled: number;
  readonly returned: number;
  /** The stock didn't cover the line when the order was placed or paid. */
  readonly backordered: boolean;
}

export interface OrderPayment {
  readonly id: string;
  readonly provider: string;
  /** The provider's payment id. */
  readonly reference: string;
  readonly status: Payment["status"];
  readonly amount: Money;
  readonly captured: Money;
  readonly refunded: Money;
  readonly createdAt: Temporal.Instant;
}

export interface QuantityLine {
  readonly lineId: string;
  readonly quantity: number;
}

export interface Fulfillment {
  readonly id: string;
  readonly status: FulfillmentStatus;
  readonly locationId: string | null;
  readonly carrier: string | null;
  readonly trackingNumber: string | null;
  readonly trackingUrl: string | null;
  readonly lines: readonly QuantityLine[];
  readonly createdAt: Temporal.Instant;
  readonly shippedAt?: Temporal.Instant;
  readonly deliveredAt?: Temporal.Instant;
}

export interface OrderReturn {
  readonly id: string;
  readonly status: ReturnStatus;
  readonly reason: string | null;
  readonly lines: readonly QuantityLine[];
  readonly createdAt: Temporal.Instant;
  readonly receivedAt?: Temporal.Instant;
}

export interface OrderRefund {
  readonly id: string;
  readonly paymentId: string;
  readonly returnId: string | null;
  readonly amount: Money;
  readonly status: OrderRefundStatus;
  readonly reason: string | null;
  readonly providerReference: string | null;
  readonly createdAt: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
}

export interface Order {
  readonly id: string;
  readonly organizationId: string;
  /** Gapless per organization, from `number-sequences` when it numbers `order`. */
  readonly number: string;
  readonly cartId: string;
  readonly customerId: string;
  readonly email: string | null;
  readonly status: OrderStatus;
  readonly currency: string;
  readonly subtotal: Money;
  readonly discountTotal: Money;
  readonly shippingTotal: Money;
  readonly taxTotal: Money;
  /** What the customer pays: with tax, unless the prices already include it. */
  readonly total: Money;
  readonly paidTotal: Money;
  readonly refundedTotal: Money;
  readonly taxInclusive: boolean;
  readonly shippingAddress?: Address;
  readonly billingAddress?: Address;
  readonly shipping?: {
    readonly rateId: string;
    readonly name: string;
    readonly amount: Money;
  };
  readonly promotions: readonly AppliedPromotion[];
  /** The tax quote the order was placed with. */
  readonly taxQuote?: TaxQuote;
  /** The sale the tax provider recorded once the order was paid. */
  readonly taxTransaction?: TaxTransaction;
  /** Gapless per organization; set once the order is paid. */
  readonly invoiceNumber: string | null;
  readonly invoicedAt?: Temporal.Instant;
  readonly placedAt: Temporal.Instant;
  readonly paidAt?: Temporal.Instant;
  readonly fulfilledAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly cancelReason: string | null;
  readonly lines: readonly OrderLine[];
  readonly payments: readonly OrderPayment[];
  readonly fulfillments: readonly Fulfillment[];
  readonly returns: readonly OrderReturn[];
  readonly refunds: readonly OrderRefund[];
}

export const amountText = (value: Money): string => value.amount.toString();

export function moneyOf(value: unknown, currency: string): Money {
  return money(BigInt(textOf(value)), currency);
}

const ADDRESS_FIELDS = [
  "name",
  "company",
  "line1",
  "line2",
  "postalCode",
  "city",
  "state",
  "phone",
] as const;

function addressOf(value: unknown): Address | undefined {
  if (!isRecord(value) || typeof value["country"] !== "string")
    return undefined;
  const fields: { -readonly [K in keyof Address]?: string } = {};
  for (const key of ADDRESS_FIELDS) {
    const entry = value[key];
    if (typeof entry === "string") fields[key] = entry;
  }
  return { ...fields, country: value["country"] };
}

function shippingOf(
  value: unknown,
  currency: string,
): PricedCart["shipping"] | undefined {
  if (!isRecord(value)) return undefined;
  return {
    rateId: textOf(value["rateId"]),
    name: textOf(value["name"]),
    amount: moneyOf(value["amount"], currency),
  };
}

function promotionsOf(
  value: unknown,
  currency: string,
): readonly AppliedPromotion[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).map((entry) => {
    const code = optionalText(entry["code"]);
    const kind = enumOrThrow(entry["kind"], PROMOTION_KINDS, "promotion kind");
    return {
      promotionId: textOf(entry["promotionId"]),
      name: textOf(entry["name"]),
      kind,
      ...(code === undefined ? {} : { code }),
      discount: moneyOf(entry["amount"] ?? "0", currency),
      freeShipping: kind === "free_shipping",
    };
  });
}

function problemsOf(value: unknown): readonly CartProblem[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isRecord).map((entry) => {
    const lineId = optionalText(entry["lineId"]);
    const variantId = optionalText(entry["variantId"]);
    const code = optionalText(entry["code"]);
    const promotionId = optionalText(entry["promotionId"]);
    const reason = optionalText(entry["reason"]);
    return {
      problem: textOf(entry["problem"]),
      ...(lineId === undefined ? {} : { lineId }),
      ...(variantId === undefined ? {} : { variantId }),
      ...(code === undefined ? {} : { code }),
      ...(promotionId === undefined ? {} : { promotionId }),
      ...(reason === undefined ? {} : { reason }),
    };
  });
}

export function pricedCartOf(value: unknown): PricedCart {
  const row = recordOf(value, "price_cart");
  const currency = textOf(row["currency"]);
  const amount = (key: string): Money => moneyOf(row[key], currency);
  const email = optionalText(row["email"]);
  const shippingAddress = addressOf(row["shippingAddress"]);
  const billingAddress = addressOf(row["billingAddress"]);
  const shipping = shippingOf(row["shipping"], currency);
  return {
    id: textOf(row["cartId"]),
    organizationId: textOf(row["organizationId"]),
    customerId: textOf(row["customerId"]),
    status: enumOrThrow(
      row["status"],
      ["open", "converted", "abandoned"] as const,
      "cart status",
    ),
    currency,
    ...(email === undefined ? {} : { email }),
    ...(shippingAddress === undefined ? {} : { shippingAddress }),
    ...(billingAddress === undefined ? {} : { billingAddress }),
    lines: recordsOf(row["lines"], "orders").map((line) => {
      const previous = line["previousUnitAmount"];
      return {
        id: textOf(line["id"]),
        variantId: textOf(line["variantId"]),
        productId: textOf(line["productId"]),
        sku: textOf(line["sku"]),
        title: textOf(line["title"]),
        quantity: Number(line["quantity"]),
        unitAmount: moneyOf(line["unitAmount"], currency),
        ...(previous === null ||
        previous === undefined ||
        previous === line["unitAmount"]
          ? {}
          : { previousUnitAmount: moneyOf(previous, currency) }),
        subtotal: moneyOf(line["subtotal"], currency),
        discount: moneyOf(line["discount"], currency),
        total: moneyOf(line["total"], currency),
        requiresShipping: line["requiresShipping"] === true,
      };
    }),
    subtotal: amount("subtotal"),
    discountTotal: amount("discountTotal"),
    shippingTotal: amount("shippingTotal"),
    total: amount("total"),
    requiresShipping: row["requiresShipping"] === true,
    weightGrams: Number(row["weightGrams"] ?? 0),
    ...(shipping === undefined ? {} : { shipping }),
    promotions: promotionsOf(row["promotions"], currency),
    problems: problemsOf(row["problems"]),
  };
}

export function shippingOptionsOf(value: unknown): readonly ShippingOption[] {
  return recordsOf(value, "orders").map((row) => ({
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    kind: enumOrThrow(row["kind"], ["flat", "weight"] as const, "rate kind"),
    amount: moneyOf(row["amount"], textOf(row["currency"])),
  }));
}

function taxLineToJson(line: TaxLine): Record<string, unknown> {
  return {
    lineId: line.lineId,
    taxable: amountText(line.taxable),
    tax: amountText(line.tax),
    rate: line.rate,
    inclusive: line.inclusive,
    ...(line.jurisdiction === undefined
      ? {}
      : { jurisdiction: line.jurisdiction }),
    ...(line.taxCategory === undefined
      ? {}
      : { taxCategory: line.taxCategory }),
  };
}

function taxLineOf(value: Record<string, unknown>, currency: string): TaxLine {
  const jurisdiction = optionalText(value["jurisdiction"]);
  const taxCategory = optionalText(value["taxCategory"]);
  return {
    lineId: textOf(value["lineId"]),
    taxable: moneyOf(value["taxable"], currency),
    tax: moneyOf(value["tax"], currency),
    rate: textOf(value["rate"]),
    inclusive: value["inclusive"] === true,
    ...(jurisdiction === undefined ? {} : { jurisdiction }),
    ...(taxCategory === undefined ? {} : { taxCategory }),
  };
}

/** The quote as `place_order` stores it: amounts as text. */
export function quoteToJson(quote: TaxQuote): Record<string, unknown> {
  return {
    provider: quote.provider,
    quoteId: quote.id,
    currency: quote.currency,
    inclusive: quote.lines.some((line) => line.inclusive),
    totalTax: amountText(quote.totalTax),
    ...(quote.expiresAt === undefined
      ? {}
      : { expiresAt: quote.expiresAt.toString() }),
    lines: quote.lines.map(taxLineToJson),
  };
}

function quoteOf(value: unknown): TaxQuote | undefined {
  if (!isRecord(value) || typeof value["quoteId"] !== "string")
    return undefined;
  const currency = textOf(value["currency"]);
  const expiresAt = optionalInstant(value["expiresAt"]);
  return {
    id: value["quoteId"],
    provider: textOf(value["provider"]),
    currency,
    lines: recordsOf(value["lines"], "orders").map((line) =>
      taxLineOf(line, currency),
    ),
    totalTax: moneyOf(value["totalTax"], currency),
    ...(expiresAt === undefined ? {} : { expiresAt }),
  };
}

export function transactionToJson(
  transaction: TaxTransaction,
): Record<string, unknown> {
  return {
    id: transaction.id,
    reference: transaction.reference,
    currency: transaction.currency,
    totalTax: amountText(transaction.totalTax),
    lines: transaction.lines.map(taxLineToJson),
  };
}

function transactionOf(value: unknown): TaxTransaction | undefined {
  if (!isRecord(value) || typeof value["id"] !== "string") return undefined;
  const currency = textOf(value["currency"]);
  return {
    id: value["id"],
    reference: textOf(value["reference"]),
    currency,
    totalTax: moneyOf(value["totalTax"], currency),
    lines: recordsOf(value["lines"], "orders").map((line) =>
      taxLineOf(line, currency),
    ),
  };
}

const quantities = (value: unknown): readonly QuantityLine[] =>
  recordsOf(value, "orders").map((line) => ({
    lineId: textOf(line["lineId"]),
    quantity: Number(line["quantity"]),
  }));

const when = (
  key: string,
  value: unknown,
): Record<string, Temporal.Instant> => {
  const instant = optionalInstant(value);
  return instant === undefined ? {} : { [key]: instant };
};

export function orderOf(value: unknown): Order {
  const row = recordOf(value, "get_order");
  const currency = textOf(row["currency"]);
  const amount = (key: string): Money => moneyOf(row[key], currency);
  const shippingAddress = addressOf(row["shippingAddress"]);
  const billingAddress = addressOf(row["billingAddress"]);
  const shipping = shippingOf(row["shipping"], currency);
  const taxQuote = quoteOf(row["tax"]);
  const taxTransaction = transactionOf(row["taxTransaction"]);
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    number: textOf(row["number"]),
    cartId: textOf(row["cartId"]),
    customerId: textOf(row["customerId"]),
    email: nullableText(row["email"]),
    status: enumOrThrow(row["status"], ORDER_STATUSES, "order status"),
    currency,
    subtotal: amount("subtotal"),
    discountTotal: amount("discountTotal"),
    shippingTotal: amount("shippingTotal"),
    taxTotal: amount("taxTotal"),
    total: amount("total"),
    paidTotal: amount("paidTotal"),
    refundedTotal: amount("refundedTotal"),
    taxInclusive: row["taxInclusive"] === true,
    ...(shippingAddress === undefined ? {} : { shippingAddress }),
    ...(billingAddress === undefined ? {} : { billingAddress }),
    ...(shipping === undefined ? {} : { shipping }),
    promotions: promotionsOf(row["promotions"], currency),
    ...(taxQuote === undefined ? {} : { taxQuote }),
    ...(taxTransaction === undefined ? {} : { taxTransaction }),
    invoiceNumber: nullableText(row["invoiceNumber"]),
    ...when("invoicedAt", row["invoicedAt"]),
    placedAt: requiredInstant(row["placedAt"], "placedAt"),
    ...when("paidAt", row["paidAt"]),
    ...when("fulfilledAt", row["fulfilledAt"]),
    ...when("completedAt", row["completedAt"]),
    ...when("cancelledAt", row["cancelledAt"]),
    cancelReason: nullableText(row["cancelReason"]),
    lines: recordsOf(row["lines"], "orders").map((line) => ({
      id: textOf(line["id"]),
      variantId: nullableText(line["variantId"]),
      productId: nullableText(line["productId"]),
      sku: textOf(line["sku"]),
      title: textOf(line["title"]),
      quantity: Number(line["quantity"]),
      unitAmount: moneyOf(line["unitAmount"], currency),
      subtotal: moneyOf(line["subtotal"], currency),
      discount: moneyOf(line["discount"], currency),
      tax: moneyOf(line["tax"], currency),
      total: moneyOf(line["total"], currency),
      requiresShipping: line["requiresShipping"] === true,
      locationId: nullableText(line["locationId"]),
      reservationId: nullableText(line["reservationId"]),
      fulfilled: Number(line["fulfilled"]),
      returned: Number(line["returned"]),
      backordered: line["backordered"] === true,
    })),
    payments: recordsOf(row["payments"], "orders").map((payment) => ({
      id: textOf(payment["id"]),
      provider: textOf(payment["provider"]),
      reference: textOf(payment["reference"]),
      status: enumOrThrow(
        payment["status"],
        PAYMENT_STATUSES,
        "payment status",
      ),
      amount: moneyOf(payment["amount"], currency),
      captured: moneyOf(payment["captured"], currency),
      refunded: moneyOf(payment["refunded"], currency),
      createdAt: requiredInstant(payment["createdAt"], "createdAt"),
    })),
    fulfillments: recordsOf(row["fulfillments"], "orders").map(
      (fulfillment) => ({
        id: textOf(fulfillment["id"]),
        status: enumOrThrow(
          fulfillment["status"],
          FULFILLMENT_STATUSES,
          "fulfillment status",
        ),
        locationId: nullableText(fulfillment["locationId"]),
        carrier: nullableText(fulfillment["carrier"]),
        trackingNumber: nullableText(fulfillment["trackingNumber"]),
        trackingUrl: nullableText(fulfillment["trackingUrl"]),
        lines: quantities(fulfillment["lines"]),
        createdAt: requiredInstant(fulfillment["createdAt"], "createdAt"),
        ...when("shippedAt", fulfillment["shippedAt"]),
        ...when("deliveredAt", fulfillment["deliveredAt"]),
      }),
    ),
    returns: recordsOf(row["returns"], "orders").map((entry) => ({
      id: textOf(entry["id"]),
      status: enumOrThrow(entry["status"], RETURN_STATUSES, "return status"),
      reason: nullableText(entry["reason"]),
      lines: quantities(entry["lines"]),
      createdAt: requiredInstant(entry["createdAt"], "createdAt"),
      ...when("receivedAt", entry["receivedAt"]),
    })),
    refunds: recordsOf(row["refunds"], "orders").map((refund) => ({
      id: textOf(refund["id"]),
      paymentId: textOf(refund["paymentId"]),
      returnId: nullableText(refund["returnId"]),
      amount: moneyOf(refund["amount"], currency),
      status: enumOrThrow(refund["status"], REFUND_STATUSES, "refund status"),
      reason: nullableText(refund["reason"]),
      providerReference: nullableText(refund["providerReference"]),
      createdAt: requiredInstant(refund["createdAt"], "createdAt"),
      ...when("completedAt", refund["completedAt"]),
    })),
  };
}

/** The tax lines of a refund: each sold line's share of `amount` out of `total`. */
export function refundedTaxLines(
  transaction: TaxTransaction,
  amount: Money,
  total: Money,
): readonly { lineId: string; amount: Money; tax: Money }[] {
  const share = (value: Money): Money => {
    if (total.amount === 0n) return value;
    const part = (value.amount * amount.amount) / total.amount;
    return money(
      part > value.amount ? value.amount : part,
      transaction.currency,
    );
  };
  return transaction.lines.map((line) => ({
    lineId: line.lineId,
    amount: share(line.taxable),
    tax: share(line.tax),
  }));
}
