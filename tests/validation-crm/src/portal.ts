import { defineSupabase } from "better-supabase";
import { tenant } from "better-supabase/plugins/tenant";
import * as v from "valibot";

import { schema } from "./generated.ts";

/** Claims of the customer portal token: the customer the contact may see. */
export const PortalClaims = v.object({
  sub: v.pipe(v.string(), v.uuid()),
  customer_id: v.pipe(v.string(), v.regex(/^\d+$/)),
});

/** Claims of a staff token: the organization the employee works in. */
export const StaffClaims = v.object({
  sub: v.pipe(v.string(), v.uuid()),
  organization_id: v.pipe(v.string(), v.uuid()),
});

/** The same tables, with `column` marked as the tenant column wherever a table has it. */
function scopedBy(column: "customerId" | "organizationId") {
  return {
    ...schema,
    meta: {
      ...schema.meta,
      tables: Object.fromEntries(
        Object.entries(schema.meta.tables).map(([key, table]) => [
          key,
          table.columns[column]
            ? { ...table, flags: { ...table.flags, tenant: column } }
            : table,
        ]),
      ),
    },
  };
}

/**
 * A contact's reads: every query on a table with `customer_id` filters on the
 * customer in the token, next to the RLS policy
 * `customer_id in (select customer_ids_with('quotes.view'))`.
 */
export const portal = defineSupabase(scopedBy("customerId"))
  .claims(PortalClaims)
  .use(tenant<v.InferOutput<typeof PortalClaims>>({ claim: "customer_id" }));

/**
 * An employee's reads, filtered on the organization in the token, next to
 * `organization_id in (select organization_ids_with('quotes.view'))`.
 */
export const staff = defineSupabase(scopedBy("organizationId"))
  .claims(StaffClaims)
  .use(tenant<v.InferOutput<typeof StaffClaims>>({ claim: "organization_id" }));
