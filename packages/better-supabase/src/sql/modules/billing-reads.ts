import type { ReadType } from "../../core/read-type.ts";
import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlRead } from "../reads.ts";

import { declareRead } from "../reads.ts";
import { userGrant } from "../shared.ts";

/** What `billing_overview` returns. */
export const BILLING_OVERVIEW_RESULT: ReadType = {
  customerId: "text?",
  accountId: "text?",
  seats: "number",
  subscription: "json",
  invoices: ["json"],
  usage: ["json"],
};

/**
 * What `billing.overview` returns. Keep it in step with
 * `BILLING_OVERVIEW_RESULT`.
 */
export interface BillingOverview {
  readonly customerId: string | null;
  readonly accountId: string | null;
  readonly seats: number;
  /** The active subscription item, or `null`. The shape of `billing.status`. */
  readonly subscription: unknown;
  /**
   * The customer's Stripe invoices, newest first, as the Sync Engine stores
   * them.
   */
  readonly invoices: readonly unknown[];
  /**
   * One status per meter, as `usage.overview` returns, empty without the
   * `usage` block.
   */
  readonly usage: readonly unknown[];
}

export const BILLING_READS: readonly BlockSqlRead[] = [
  declareRead(
    "overview",
    "billing_overview",
    {
      organizationId: { param: "tenant", type: "id" },
      invoiceLimit: { param: "invoice_limit", type: "int", optional: true },
    },
    BILLING_OVERVIEW_RESULT,
    "The billing page in one call: the Stripe customer, the seat count, the subscription item, the latest invoices and the usage against each quota.",
    ["customers", "subscriptions"],
  ),
];

/**
 * `billing_overview`: `billing_status`, `billing_invoices` and, with the usage
 * block installed, `usage_overview`. Each checks the caller's permission.
 */
export function billingReads(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const id = ctx.idType;

  const usage =
    ctx.installed("usage") && ctx.of("usage").mode !== "custom"
      ? `${ctx.of("usage").fn("usage_overview")}(billing_overview.tenant)`
      : "'[]'::jsonb";

  return `
-- The billing page in one call. It runs as the caller and reads through the
-- status, invoice and usage functions, which check billing and usage reads.
create or replace function ${fn("billing_overview")}(tenant ${id}, invoice_limit integer default 10)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_status jsonb := ${fn("billing_status")}(billing_overview.tenant);
begin
  return jsonb_build_object(
    'customerId', v_status -> 'customer',
    'accountId', v_status -> 'account',
    'seats', coalesce((v_status ->> 'seats')::integer, 0),
    'subscription', coalesce(v_status -> 'subscription', 'null'::jsonb),
    'invoices', coalesce(${fn("billing_invoices")}(billing_overview.tenant, billing_overview.invoice_limit), '[]'::jsonb),
    'usage', coalesce(${usage}, '[]'::jsonb)
  );
end;
$$;
${userGrant(`${fn("billing_overview")}(${id}, integer)`)}
`;
}
