import { createHono } from "better-supabase/hono";
import { defineListQuery } from "better-supabase/list";

import { betterSupabase } from "./lib/supabase";
import { partnerApi } from "./marketplace";
import { authorize, jwks, token } from "./oauth";

const bsb = createHono(betterSupabase);

const customers = defineListQuery(betterSupabase, "customers", {
  search: ["name"],
  facets: { status: "status" },
  sorts: { name: { name: "asc" }, newest: { createdAt: "desc" } },
  defaultSort: "name",
  pageSize: 20,
});

/** The fixture's token hook writes the role to the top-level `user_role` claim. */
const admins = bsb.require({
  roles: ["admin"],
  roleClaim: "user_role",
  requireOrganization: true,
});

/**
 * `bsb.app()` installs `bsb.onError`: a thrown `DbException`, such as an
 * `.orThrow()` in a block call, answers as RFC 9457 Problem Details.
 */
const app = bsb
  .app()
  // Registered before the `/api/*` middleware: Vercel sends its own OIDC
  // token as the bearer, which the handler verifies and Supabase Auth can't.
  .all("/api/vercel/*", (c) => partnerApi(c.req.raw))
  .post("/oauth/token", (c) => token(c.req.raw))
  .get("/.well-known/jwks.json", () => jwks())
  .post("/oauth/authorize", bsb.middleware({ allow: ["user"] }), async (c) => {
    if (c.var.auth.kind !== "user") {
      return c.json({ error: "login_required" }, 401);
    }

    const params = new URLSearchParams(await c.req.text());
    const redirect = await authorize({ userId: c.var.auth.user.id, params });

    return c.json({ redirect: redirect.href });
  })
  .use("/api/*", bsb.middleware())
  .get("/api/me", (c) => c.json({ kind: c.var.auth.kind }))
  .route(
    "/api/customers",
    bsb.resource("customers", {
      list: customers,
      select: ["id", "name", "status", "organizationId", "createdAt"],
    }),
  )
  .get("/api/customers/:id/notes", async (c) => {
    const notes = await c.var.db.notes
      .list({
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
