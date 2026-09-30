export type Feature = {
  readonly title: string;
  readonly body: string;
  readonly href: string;
};

export const features: readonly Feature[] = [
  {
    title: "Stronger generated types",
    body: "gen wraps supabase gen types and adds relationship cardinality, unique keys, CHECK-constraint unions, typed jsonb and camelCase column maps.",
    href: "/docs/cli/gen",
  },
  {
    title: "A typed repository",
    body: "findMany with where, include, orderBy and pagination compiles to one PostgREST request, or to SQL on the direct-Postgres path.",
    href: "/docs/repository",
  },
  {
    title: "Results, not exceptions",
    body: "Every call returns a Result with a plain, serializable DbError. Return it from server actions and RPC handlers; .orThrow() is opt-in.",
    href: "/docs/concepts/results",
  },
  {
    title: "Your casing, everywhere",
    body: "Keep database names with casing: 'snake', or get camelCase rows renamed inside the PostgREST query itself.",
    href: "/docs/concepts/casing",
  },
  {
    title: "Auth without extra round trips",
    body: "Valid access tokens never touch the Auth server. Refresh happens once, in the proxy, and is single-flighted.",
    href: "/docs/auth",
  },
  {
    title: "Cache tags that follow writes",
    body: "Mutations invalidate bs:<table> and bs:<table>:<id>, with read-your-writes inside Next.js server actions.",
    href: "/docs/concepts/caching",
  },
  {
    title: "Plugins",
    body: "Timestamps, soft delete, tenants, actors, validation and rules, each versioned and opt-in.",
    href: "/docs/plugins",
  },
  {
    title: "Kits",
    body: "List pages, storage paths, realtime topics, background jobs and SQL modules you can sync into migrations.",
    href: "/docs/kits/list",
  },
];

export const frameworks: readonly Feature[] = [
  {
    title: "Next.js",
    body: "Proxy, Server Components, route handlers, server actions and cache tags.",
    href: "/docs/frameworks/next",
  },
  {
    title: "Hono",
    body: "Middleware, Result-aware handlers and REST resources that match your OpenAPI document.",
    href: "/docs/frameworks/hono",
  },
  {
    title: "oRPC",
    body: "A middleware that adds the caller’s repositories to the oRPC context.",
    href: "/docs/frameworks/orpc",
  },
  {
    title: "Edge Functions",
    body: "Fetch handlers for Supabase Edge Functions, Deno, Bun and Workers.",
    href: "/docs/frameworks/edge",
  },
  {
    title: "MCP",
    body: "Tools from your tables and your own code, running as the signed-in user.",
    href: "/docs/frameworks/mcp",
  },
  {
    title: "React and TanStack Query",
    body: "Typed query and mutation options for every table, with table-based invalidation.",
    href: "/docs/frontend/query",
  },
];

export const runtimes: readonly string[] = [
  "Node.js",
  "Deno",
  "Bun",
  "Cloudflare Workers",
  "Vercel Functions",
  "Supabase Edge Functions",
];

export const getStartedSteps: readonly {
  readonly title: string;
  readonly body: string;
}[] = [
  { title: "Install", body: "pnpm add better-supabase @supabase/supabase-js" },
  {
    title: "Init",
    body: "better-supabase init writes the config, the client and framework glue.",
  },
  {
    title: "Generate",
    body: "better-supabase gen reads your local stack and writes typed models.",
  },
  {
    title: "Query",
    body: "connect() per request with the user’s client, so RLS always applies.",
  },
];

export const faq: readonly {
  readonly question: string;
  readonly answer: string;
}[] = [
  {
    question: "Does it replace supabase-js?",
    answer:
      "No. better-supabase is built on @supabase/supabase-js, @supabase/server, @supabase/ssr and @supabase/middleware. The raw client stays one property away as $client.",
  },
  {
    question: "Does Row Level Security still apply?",
    answer:
      "Yes. defineSupabase holds no secrets and no connection. You call connect() per request with the client for the current user, so every query runs under their RLS policies.",
  },
  {
    question: "Do I need a direct Postgres connection?",
    answer:
      "No. Queries go through PostgREST by default. The direct-Postgres path is optional, for jobs and scripts that need SQL.",
  },
  {
    question: "Which runtimes and TypeScript versions are supported?",
    answer:
      "Runtime entries import no Node built-ins, so they run on every WinterTC runtime. Published types are tested against TypeScript 5.9, 6 and 7.",
  },
  {
    question: "Is this an official Supabase project?",
    answer:
      "No. better-supabase is an independent, MIT-licensed open-source project built on the official Supabase packages.",
  },
];
