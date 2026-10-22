import { bsb } from "@/lib/supabase/server";

// Compile-time only: the tables in `appTables` get typed repositories like
// the fixture's own tables.
export const POST = bsb.route(async (_request, { db }) => {
  const project = await db.projects
    .create(
      { organizationId: "org", name: "Launch", budgetMinor: 250_000n },
      { select: ["id", "currency"] },
    )
    .orThrow();

  await db.savedViews
    .create({ name: "Active", filters: { status: "active" } })
    .orThrow();

  // @ts-expect-error a project belongs to an organization
  await db.projects.create({ name: "No organization" });

  const [counted] = await db.projectsView
    .findMany({ select: ["openTasks", "nextDueOn"], limit: 1 })
    .orThrow();

  const openTasks: bigint | null | undefined = counted?.openTasks;
  const nextDueOn: string | null | undefined = counted?.nextDueOn;

  const [task] = await db.tasksView
    .findMany({ select: ["projectName"], limit: 1 })
    .orThrow();

  const projectName: string | null | undefined = task?.projectName;

  // @ts-expect-error the view of rollups and lookups is read-only
  await db.projectsView.create({ organizationId: "org", name: "Launch" });

  return {
    id: project.id,
    currency: project.currency,
    openTasks: openTasks?.toString(),
    nextDueOn,
    projectName,
  };
});
