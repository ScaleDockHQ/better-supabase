import { createHono } from "better-supabase/hono";
import { defineListQuery } from "better-supabase/list";

import { betterSupabase } from "./lib/supabase";

const bs = createHono(betterSupabase);

const customers = defineListQuery(betterSupabase, "customers", {
  search: ["name"],
  facets: { status: "status" },
  sorts: { name: { name: "asc" }, newest: { createdAt: "desc" } },
  defaultSort: "name",
  pageSize: 20,
});

/** The fixture's token hook writes the role to the top-level `user_role` claim. */
const admins = bs.require({
  roles: ["admin"],
  roleClaim: "user_role",
  requireTenant: true,
});

const app = bs
  .app()
  .use("/api/*", bs.middleware())
  .get("/api/me", (c) => c.json({ kind: c.var.auth.kind }))
  .route(
    "/api/customers",
    bs.resource("customers", {
      list: customers,
      select: ["id", "name", "status", "organizationId", "createdAt"],
    }),
  )
  .get("/api/customers/:id/notes", async (c) => {
    const notes = await c.var.db.notes
      .findMany({
        select: ["id", "body", "kind", "createdAt"],
        where: { customerId: c.req.param("id") },
        orderBy: { createdAt: "desc" },
      })
      .orThrow();
    return c.json({ items: notes });
  })
  .post("/api/customers/:id/archive", admins, async (c) => {
    const customer = await c.var.db.customers
      .update(
        c.req.param("id"),
        { status: "archived" },
        { select: ["id", "status"] },
      )
      .orThrow();
    return c.json(customer);
  });

export default app;
