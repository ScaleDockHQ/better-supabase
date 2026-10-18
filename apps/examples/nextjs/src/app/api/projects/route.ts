import { bs } from "../../../lib/supabase/server";

export const GET = bs.route((_request, { db }) =>
  db.projects.findMany({
    select: ["id", "name", "budgetMinor", "currency", "labelId"],
    orderBy: { name: "asc" },
    limit: 50,
  }),
);
