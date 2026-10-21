import { type ContractOf, defineFunction } from "better-supabase/edge";
import * as v from "valibot";

import { bs } from "./server.ts";

/**
 * Runs as the caller, so RLS decides whether the organization accepts the row.
 * A body the input rejects answers 422 before the handler runs.
 */
export const createCustomer = defineFunction(bs, {
  input: v.object({
    name: v.pipe(v.string(), v.trim(), v.minLength(1)),
    organizationId: v.pipe(v.string(), v.uuid()),
  }),
  output: v.object({
    id: v.string(),
    name: v.string(),
    organizationId: v.string(),
  }),
  handler: (input, { db }) =>
    db.customers.create(input, { select: ["id", "name", "organizationId"] }),
});

/** What `functions<Contracts>()` in the app calls this function with. */
export type CreateCustomer = ContractOf<typeof createCustomer>;
