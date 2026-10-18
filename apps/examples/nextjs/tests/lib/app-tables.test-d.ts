import { bs } from "@/lib/supabase/server";

// Compile-time only: the tables in `appTables` get typed repositories like
// the fixture's own tables.
export const POST = bs.route(async (_request, { db }) => {
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

  return { id: project.id, currency: project.currency };
});
