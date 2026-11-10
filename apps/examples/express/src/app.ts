import { guard, problemErrorHandler, toExpress } from "better-supabase/node";
import {
  createServer,
  cronHandler,
  observedFetch,
  withBetterSupabase,
} from "better-supabase/server";
import express from "express";

import { betterSupabase } from "./lib/supabase/index.ts";

/** Supabase calls of the process by status, for a metrics endpoint. */
export const supabaseCalls = new Map<string, number>();

const bsb = createServer(betterSupabase, {
  fetch: observedFetch({
    onCall: ({ status }) => {
      const key = String(status ?? "error");

      supabaseCalls.set(key, (supabaseCalls.get(key) ?? 0) + 1);
    },
  }),
});

/**
 * A cron route that counts the customers as the service role. Mount it where
 * the scheduler calls, with the secret the deployment sets.
 */
export const customersCron = (secret: string) =>
  cronHandler(bsb, { name: "customers", secret }, async (ctx) => ({
    customers: await ctx.db.customers.count().orThrow(),
  }));

const customer = ["id", "name", "status", "organizationId"] as const;

/** The fixture's token hook writes the role to the top-level `user_role` claim. */
const admins = guard({
  roles: ["admin"],
  roleClaim: "user_role",
  requireTenant: true,
});

export const app = express()
  .use("/api", toExpress([withBetterSupabase(bsb, { allow: ["user"] })]))
  .get("/api/me", (_req, res) => {
    res.json({ kind: res.locals.bsb.auth.kind, tenant: res.locals.tenant });
  })
  .get("/api/customers", async (_req, res) => {
    res.json(
      await res.locals.db.customers
        .list({ select: customer, orderBy: { name: "asc" }, limit: 50 })
        .orThrow(),
    );
  })
  .get("/api/customers/:id", async (req, res) => {
    res.json(
      await res.locals.db.customers
        .get(req.params.id, { select: customer })
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
