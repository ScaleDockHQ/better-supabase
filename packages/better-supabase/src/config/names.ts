/** The steps `better-supabase gen` runs, in the order it runs them. */
export const GEN_TASKS = ["types", "sql", "spec", "seed", "env"] as const;

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

/**
 * An integration as `init`, `add` and `/create` show it, and the integrations
 * it needs.
 */
export interface IntegrationInfo {
  readonly title: string;
  /** What `init` or `add` writes, one sentence. */
  readonly description: string;
  readonly requires: readonly (typeof INTEGRATION_NAMES)[number][];
}

export const INTEGRATION_INFO: Readonly<
  Record<(typeof INTEGRATION_NAMES)[number], IntegrationInfo>
> = {
  client: {
    title: "Browser client",
    description:
      "A browser client with cookie sessions shared with the server.",
    requires: [],
  },
  next: {
    title: "Next.js",
    description:
      "The proxy, and helpers for Server Components, route handlers and actions.",
    requires: ["client"],
  },
  react: {
    title: "React",
    description: "A React provider and typed TanStack Query hooks.",
    requires: ["client"],
  },
  hono: {
    title: "Hono",
    description: "Hono middleware, handlers and REST resources.",
    requires: [],
  },
  orpc: {
    title: "oRPC",
    description: "oRPC middleware with a typed context and ORPCError mapping.",
    requires: [],
  },
  edge: {
    title: "Edge Function",
    description: "A Supabase Edge Function with CORS and Problem Details.",
    requires: [],
  },
  expo: {
    title: "Expo",
    description:
      "Expo Router server loaders, API routes and middleware, and a native client.",
    requires: ["client"],
  },
  mcp: {
    title: "MCP server",
    description: "An MCP server over Streamable HTTP, as an Edge Function.",
    requires: [],
  },
};

/** The agent folders `better-supabase skills install` writes to. */
export const SKILLS_AGENTS = ["cursor", "claude", "agents"] as const;
