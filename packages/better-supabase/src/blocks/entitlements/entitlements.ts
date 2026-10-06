import type { SqlClient } from "../../postgres/executor.ts";

import { AsyncResult } from "../../core/result.ts";
import { run } from "../shared.ts";

/** The Stripe event sent when a customer's active entitlements change. */
export const ENTITLEMENTS_UPDATED =
  "entitlements.active_entitlement_summary.updated";

function stripeCustomerOf(payload: unknown): string | undefined {
  if (typeof payload !== "object" || payload === null) return undefined;
  // SAFETY: payload is a non-null object, and every nested field is optional and checked.
  const object = (payload as { data?: { object?: { customer?: unknown } } })
    .data?.object;
  const customer = object?.customer;
  if (typeof customer === "string") return customer;
  // SAFETY: a Stripe customer is an id string or an object with an id; the
  // string case returned above.
  const id = (customer as { id?: unknown } | undefined)?.id;
  return typeof id === "string" ? id : undefined;
}

/**
 * Users whose `memberships` claim carries the entitlements of the Stripe
 * customer in an `entitlements.active_entitlement_summary.updated` event, so
 * a job can invalidate their sessions. Empty for other payloads.
 */
export function entitlementMembers(
  sql: SqlClient,
  payload: unknown,
): AsyncResult<readonly string[]> {
  const customer = stripeCustomerOf(payload);
  if (customer === undefined) return AsyncResult.ok([]);
  return run(() =>
    sql.queryRaw<{ user_id: string }>(
      "select user_id from better_supabase.entitlement_members($1) as user_id",
      [customer],
    ),
  ).map((rows) => rows.map((row) => row.user_id));
}
