/** The steps `better-supabase gen` runs, in the order it runs them. */
export const GEN_TASKS = [
  "types",
  "sql",
  "spec",
  "seed",
  "scaffold",
  "env",
] as const;

/** Glue `better-supabase init` and `add` write for a framework or runtime. */
export const INTEGRATION_NAMES = [
  "next",
  "hono",
  "orpc",
  "edge",
  "expo",
  "mcp",
  "client",
  "react",
] as const;

/** The agent folders `better-supabase skills install` writes to. */
export const SKILLS_AGENTS = ["cursor", "claude", "agents"] as const;
