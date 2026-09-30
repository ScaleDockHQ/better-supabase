import { next } from "../../../../lib/supabase.server";

export const GET = next.route<{ id: string }>((_request, { db, params }) =>
  db.customers.findById(params.id, {
    select: ["id", "name", "status", "organizationId"],
  }),
);

/** Deleting needs a second factor verified in this session. */
export const DELETE = next.route<{ id: string }>(
  (_request, { db, params }) => db.customers.delete(params.id),
  { aal: "aal2" },
);
