import { bs } from "../../../../lib/supabase/server";

/**
 * The REST API for the API model, as the caller (RLS): `GET /api/v1/customers`,
 * `GET|PATCH|DELETE /api/v1/customers/{id}` and the `archive` action. Paths
 * outside the map answer 404 before auth resolves.
 */
export const { GET, POST, PATCH, PUT, DELETE } = bs.resources(
  {
    customers: {
      operations: ["list", "get", "update", "delete"],
      select: ["id", "name", "status", "organizationId"],
      actions: {
        archive: {
          method: "POST",
          path: "/{id}/archive",
          summary: "Archive a customer",
          handler: (ctx, { id }) =>
            ctx.db.customers.update(
              String(id),
              { status: "archived" },
              { select: ["id", "status"] },
            ),
        },
      },
    },
  },
  { basePath: "/api/v1" },
);
