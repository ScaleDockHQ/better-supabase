import { createEdge } from "better-supabase/edge";

import { betterSupabase } from "../_shared/supabase.ts";

const bs = createEdge(betterSupabase, { cors: true });

const customer = ["id", "name", "status", "organizationId"] as const;

/** The fixture's token hook writes the role to the top-level `user_role` claim. */
const admin = { roles: ["admin"], roleClaim: "user_role" } as const;

/**
 * Every route runs as the caller, so RLS decides the rows. Unknown paths
 * answer 404 and wrong methods 405 before auth resolves.
 */
export const handler = bs.routes(
  {
    "GET /me": (_request, { auth, tenant }) => ({ kind: auth.kind, tenant }),
    "GET /customers": (_request, { db }) =>
      db.customers.findMany({
        select: customer,
        orderBy: { name: "asc" },
        limit: 50,
      }),
    "GET /customers/:id": (_request, { db, params }) =>
      db.customers.findById(params.id, { select: customer }),
    "POST /customers/:id/archive": {
      ...admin,
      requireTenant: true,
      handler: (_request, { db, params }) =>
        db.customers.update(
          params.id,
          { status: "archived" },
          { select: customer },
        ),
    },
    "GET /tags": (_request, { db }) =>
      db.tags.findMany({ select: ["id", "name"], orderBy: { name: "asc" } }),
  },
  { basePath: "/api" },
);
