import { bs } from "../../../../lib/supabase/server";

export const GET = bs.route<{ id: string }>((_request, { db, params }) =>
  db.customers.findById(params.id, {
    select: ["id", "name", "status", "organizationId"],
  }),
);

/** Deleting needs a second factor verified in this session. */
export const DELETE = bs.route<{ id: string }>(
  (_request, { db, params }) => db.customers.delete(params.id),
  { aal: "aal2" },
);
