import type { StripeTaxId } from "../stripe.ts";
import type { StripeEvent, SubscriptionItem } from "./types.ts";

import { dbError } from "../../core/errors.ts";
import {
  AsyncResult,
  err,
  ok,
  type Result,
  toDbError,
} from "../../core/result.ts";
import { isRecord, optionalText, textOf } from "../shared.ts";

export const ORGANIZATION_KEY = "organization_id";

export const SEAT_EVENT: RegExp =
  /(?:^|\.)organization\.(?:member_added|member_removed|member_left|role_changed)$/;

export function subscriptionItemOf(
  value: unknown,
): SubscriptionItem | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    subscriptionId: textOf(value["subscription"]),
    itemId: textOf(value["item"]),
    price: optionalText(value["price"]),
    quantity: Number(value["quantity"] ?? 0),
    status: textOf(value["status"]),
  };
}

/** A row of `billing_tax_ids` as Stripe's tax id object. */
export function syncedTaxId(
  row: Readonly<Record<string, unknown>>,
): StripeTaxId {
  const verification = row["verification"];
  const raw = row["created"];

  const created =
    typeof raw === "number" || (typeof raw === "string" && /^\d+$/.test(raw))
      ? Number(raw)
      : Number.NaN;

  return {
    id: textOf(row["id"]),
    type: textOf(row["type"]),
    value: textOf(row["value"]),
    country: optionalText(row["country"]) ?? null,
    verification: isRecord(verification)
      ? { status: optionalText(verification["status"]) ?? null }
      : null,
    created: Number.isSafeInteger(created) ? created : null,
  };
}

export const customerIdOf = (value: unknown): string | undefined => {
  if (typeof value === "string") {
    return value;
  }

  return isRecord(value) ? optionalText(value["id"]) : undefined;
};

export const metadataTenant = (
  object: Readonly<Record<string, unknown>>,
): string | undefined => {
  const metadata = object["metadata"];

  return isRecord(metadata)
    ? optionalText(metadata[ORGANIZATION_KEY])
    : undefined;
};

export function isStripeEvent(value: unknown): value is StripeEvent {
  return (
    isRecord(value) &&
    typeof value["id"] === "string" &&
    typeof value["type"] === "string" &&
    isRecord(value["data"])
  );
}

/**
 * `extra` merged into `base`: nested objects merge, arrays and other values
 * replace.
 */
function deepMerge(
  base: Readonly<Record<string, unknown>>,
  extra: Readonly<Record<string, unknown>>,
): Record<string, unknown> {
  const merged: Record<string, unknown> = { ...base };

  for (const [key, value] of Object.entries(extra)) {
    const current = merged[key];
    merged[key] =
      isRecord(current) && isRecord(value) ? deepMerge(current, value) : value;
  }

  return merged;
}

/**
 * The block's Checkout Session parameters with the app's `params` merged in
 * deeply, then the customer, `client_reference_id` and the tenant metadata (on
 * the session and, for a subscription, on `subscription_data`) set again, so
 * `params` adds metadata without dropping the link the webhook needs.
 */
export function checkoutParams(
  base: Readonly<Record<string, unknown>>,
  extra: Readonly<Record<string, unknown>> | undefined,
  organizationId: string,
  customerId: string,
): Record<string, unknown> {
  const merged = extra === undefined ? { ...base } : deepMerge(base, extra);
  const tenant = { metadata: { [ORGANIZATION_KEY]: organizationId } };

  return deepMerge(merged, {
    customer: customerId,
    client_reference_id: organizationId,
    ...tenant,
    ...(merged["mode"] === "subscription" ? { subscription_data: tenant } : {}),
  });
}

/** Stripe calls as results: a thrown Stripe error becomes a `DbError`. */
export function stripeCall<T>(work: () => Promise<T>): AsyncResult<T> {
  return AsyncResult.from(async () => {
    try {
      return ok(await work());
    } catch (cause) {
      return err(toDbError(cause));
    }
  });
}

const isoOfEpoch = (value: unknown): string | undefined =>
  typeof value === "number" && Number.isFinite(value)
    ? new Date(value * 1000).toISOString()
    : undefined;

/**
 * The arguments of `upsert_billing_subscription` for a
 * `customer.subscription.*` object.
 */
export function subscriptionRecord(
  tenant: string,
  object: Readonly<Record<string, unknown>>,
  created: number | undefined,
): Readonly<Record<string, unknown>> {
  const items = isRecord(object["items"]) ? object["items"]["data"] : undefined;

  const first =
    Array.isArray(items) && isRecord(items[0]) ? items[0] : undefined;

  const price = first && isRecord(first["price"]) ? first["price"] : undefined;

  return {
    tenant,
    subscription: textOf(object["id"]),
    status: optionalText(object["status"]) ?? "incomplete",
    price: price ? optionalText(price["id"]) : undefined,
    period_end: isoOfEpoch(
      object["current_period_end"] ?? first?.["current_period_end"],
    ),
    cancel_at: isoOfEpoch(object["cancel_at"]),
    event_at: isoOfEpoch(created) ?? new Date().toISOString(),
  };
}

/**
 * The `conflict` error `checkout` returns for a tenant billed elsewhere or
 * already subscribed.
 */
export function checkoutBlockedError(reason: string): Result<never> {
  const [hint = "BILLING_ALREADY_SUBSCRIBED", provider] = reason.split(":", 2);

  return err(
    dbError(
      "conflict",
      provider
        ? `This tenant is billed through ${provider}`
        : "This tenant already has a subscription",
      { hint },
    ),
  );
}
