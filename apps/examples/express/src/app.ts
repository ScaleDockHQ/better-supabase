import { guard, problemErrorHandler, toExpress } from "better-supabase/node";
import { createServer, withBetterSupabase } from "better-supabase/server";
import express from "express";

import { betterSupabase } from "./lib/supabase/index.ts";

const bs = createServer(betterSupabase);

const customer = ["id", "name", "status", "organizationId"] as const;

/** The fixture's token hook writes the role to the top-level `user_role` claim. */
const admins = guard({
  roles: ["admin"],
  roleClaim: "user_role",
  requireTenant: true,
});

export const app = express()
  .use("/api", toExpress([withBetterSupabase(bs, { allow: ["user"] })]))
  .get("/api/me", (_req, res) => {
    res.json({ kind: res.locals.bs.auth.kind, tenant: res.locals.tenant });
  })
  .get("/api/customers", async (_req, res) => {
    res.json(
      await res.locals.db.customers
        .findMany({ select: customer, orderBy: { name: "asc" }, limit: 50 })
        .orThrow(),
    );
  })
  .get("/api/customers/:id", async (req, res) => {
    res.json(
      await res.locals.db.customers
        .findById(req.params.id, { select: customer })
        .orThrow(),
    );
  })
  .post("/api/customers/:id/archive", admins, async (req, res) => {
    res.json(
      await res.locals.db.customers
        .update(req.params.id, { status: "archived" }, { select: customer })
        .orThrow(),
    );
  })
  .use(problemErrorHandler());
