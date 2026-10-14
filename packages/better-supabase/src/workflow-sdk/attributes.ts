/** The attributes the Supabase World's status trigger copies into `workflow_runs`. */
export const WORKFLOW_ATTRIBUTES = {
  tenant: "bs.tenant",
  actor: "bs.actor",
  key: "bs.key",
  /** The builder definition a run started from; its alerts match on it. */
  definition: "bs.definition",
  /** The builder version number a run started from. */
  version: "bs.version",
  /** The opaque ticket `bs.forContext` resolves into the context a step runs as. */
  ticket: "bs.ticket",
} as const;
