import type { StripeTaxId } from "../stripe.ts";
import type { StripeEvent, SubscriptionItem } from "./types.ts";

import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
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

/** `extra` merged into `base`: nested objects merge, arrays and other values replace. */
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
 * deeply, then the customer, `client_reference_id` and the tenant metadata
 * (on the session and, for a subscription, on `subscription_data`) set
 * again, so `params` adds metadata without dropping the link the webhook needs.
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
