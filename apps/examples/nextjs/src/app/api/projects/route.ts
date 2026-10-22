import { bsb } from "../../../lib/supabase/server";

// `projects_view` adds the task rollups, read with the caller's row level
// security.
export const GET = bsb.route((_request, { db }) =>
  db.projectsView.findMany({
    select: [
      "id",
      "name",
      "budgetMinor",
      "currency",
      "labelId",
      "openTasks",
      "doneTasks",
      "nextDueOn",
    ],
    orderBy: { name: "asc" },
    limit: 50,
  }),
);
