import { bsb } from "../../../../lib/supabase/server";

export const GET = bsb.route<{ id: string }>((_request, { db, params }) =>
  db.customers.get(params.id, {
    select: ["id", "name", "status", "organizationId"],
  }),
);

/** Deleting needs a second factor verified in this session. */
export const DELETE = bsb.route<{ id: string }>(
  (_request, { db, params }) => db.customers.delete(params.id),
  { aal: "aal2" },
);
