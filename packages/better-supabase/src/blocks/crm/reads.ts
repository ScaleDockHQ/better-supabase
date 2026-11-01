import { compositeReadSet } from "../composite-reads.ts";

/**
 * The pipeline page of `crm`: the board of one pipeline. Build it with
 * `defineCompositeReadSet(betterSupabase, crmReadSets.dashboard, reads)` after
 * `better-supabase gen` has written the block reads.
 */
export const crmReadSets: {
  readonly dashboard: ReturnType<
    typeof compositeReadSet<"crm_dashboard", { readonly pipelineId: "uuid" }>
  >;
} = {
  dashboard: compositeReadSet(
    "crm_dashboard",
    { pipelineId: "uuid" },
    {
      board: {
        block: "deals",
        read: "board",
        args: { pipelineId: "pipelineId" },
      },
    },
  ),
};
