import { createHono } from "better-supabase/hono";

import {
  billableCustomers,
  billingAddress,
} from "@better-supabase/example-monorepo-billing";
import { activeCustomers } from "@better-supabase/example-monorepo-crm";
import { betterSupabase } from "@better-supabase/example-monorepo-runtime";

const bs = createHono(betterSupabase);

const app = bs
  .app()
  .use("/api/*", bs.middleware())
  .get(
    "/api/customers",
    bs.handler((_c, { db }) => activeCustomers(db)),
  )
  .get("/api/customers/:id/billing-address", async (c) =>
    c.json(await billingAddress(c.var.db, c.req.param("id")).orThrow()),
  )
  .get("/api/organizations/:id/seats", async (c) =>
    c.json(await billableCustomers(c.var.db, c.req.param("id")).orThrow()),
  );

export default app;
