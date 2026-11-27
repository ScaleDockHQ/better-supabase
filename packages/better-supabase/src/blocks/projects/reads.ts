import { compositeReadSet } from "../composite-reads.ts";

/**
 * The project page of `projects`: one project row. Build it with
 * `defineCompositeReadSet(betterSupabase, projectsReadSets.overview, reads)`
 * after `better-supabase gen` has written the block reads. The rest of the page
 * (`overview()`) reads the other parts in parallel.
 */
export const projectsReadSets: {
  readonly overview: ReturnType<
    typeof compositeReadSet<
      "projects_overview",
      { readonly organizationId: "uuid"; readonly projectId: "uuid" }
    >
  >;
} = {
  overview: compositeReadSet(
    "projects_overview",
    { organizationId: "uuid", projectId: "uuid" },
    {
      project: {
        block: "tasks",
        read: "project",
        args: { projectId: "projectId" },
      },
    },
  ),
};
