import type { Snippet } from "@/lib/snippets";

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
    body: "list with where, include, orderBy and pagination compiles to one PostgREST request, or to SQL on the direct-Postgres path.",
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
    body: "Mutations invalidate bsb:<table> and bsb:<table>:<id>, with read-your-writes inside Next.js server actions.",
    href: "/docs/concepts/caching",
  },
  {
    title: "Block extensions",
    body: "Timestamps, soft delete, organization scoping, actor columns and validation, installed by gen with their blocks.",
    href: "/docs/blocks/updated-at",
  },
  {
    title: "Blocks",
    body: "List pages, storage paths, realtime topics, background jobs and SQL modules you can sync into migrations.",
    href: "/docs/platform/list",
  },
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
    question: "Do I have to rebuild my schema?",
    answer:
      "No. Every step of adoption is optional and reversible. You can type your existing tables first, tag one table, and run a block over it later. Blocks that bring their own tables can sit next to yours.",
  },
  {
    question: "Who owns the SQL a block generates?",
    answer:
      "You do. A block renders tables, policies and functions into files in your repository. You review them, commit them and change them like the rest of your schema, and doctor checks the result.",
  },
  {
    question: "Does it replace supabase-js?",
    answer:
      "No. better-supabase is built on @supabase/supabase-js, @supabase/server, @supabase/ssr and @supabase/middleware. The raw client stays one property away as $client.",
  },
  {
    question: "Does Row Level Security still apply?",
    answer:
      "Yes. createSupabase holds no secrets and no connection. You call connect() per request with the client for the current user, so every query runs under their RLS policies.",
  },
  {
    question: "Do I need a direct Postgres connection?",
    answer:
      "No. Queries go through PostgREST by default. The direct-Postgres path is optional, for jobs and scripts that need SQL.",
  },
  {
    question: "Which runtimes and TypeScript versions are supported?",
    answer:
      "Runtime entries import no Node built-ins, so they run on every WinterTC runtime. Published types are tested against TypeScript 6 and 7.",
  },
  {
    question: "Is this an official Supabase project?",
    answer:
      "No. better-supabase is an independent, MIT-licensed open-source project built on the official Supabase packages.",
  },
];

export const howItWorks: readonly {
  readonly title: string;
  readonly body: string;
  readonly snippet: Snippet;
}[] = [
  {
    title: "Your tables stay yours",
    body: "Tables are plain SQL files in supabase/schemas. Nothing is generated over them, and you can start from the tables you already have.",
    snippet: {
      filename: "supabase/schemas/public/tables/invoices.sql",
      language: "sql",
      code: `create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  number text not null,
  total_cents bigint not null
);`,
    },
  },
  {
    title: "Tags turn features on",
    body: "A feature is a tag in the table comment. The CLI edits it for you, and the free text of the comment stays.",
    snippet: {
      filename: "terminal",
      language: "bash",
      code: `pnpm better-supabase table invoices enable realtime
pnpm better-supabase table invoices enable audit

# comment on table invoices is 'Invoices. @bsb realtime; audit'`,
    },
  },
  {
    title: "Blocks emit the SQL",
    body: "A block renders tables, policies and functions into files you read and commit. Add one over a table you own, or install a preset.",
    snippet: {
      filename: "terminal",
      language: "bash",
      code: `pnpm better-supabase add comments --over public.invoices
pnpm better-supabase add --preset crm
pnpm better-supabase doctor`,
    },
  },
  {
    title: "A typed client on top",
    body: "gen reads the result and types every table, so the repository, the validators and the hooks match your schema.",
    snippet: {
      filename: "app/invoices/page.tsx",
      language: "tsx",
      code: `const { db } = await bsb.context();

const result = await db.invoices.list({
  where: { total_cents: { gt: 0 } },
  orderBy: { number: "desc" },
});

if (!result.ok) return <ErrorState error={result.error} />;`,
    },
  },
];

export const adoptLadder: readonly {
  readonly command: string;
  readonly title: string;
  readonly body: string;
}[] = [
  {
    command: "init",
    title: "Write a config",
    body: "On an existing project it writes a config with no blocks and no SQL, and changes nothing in the database.",
  },
  {
    command: "gen",
    title: "Type every table",
    body: "Repositories, validators and hooks for the tables you already have.",
  },
  {
    command: "table <t> enable <feature>",
    title: "Tag a table",
    body: "Realtime, audit, search or subjects for one table, through a tag in its comment.",
  },
  {
    command: "add <block> --over <table>",
    title: "Run a block over your table",
    body: "A block's files render over a table you own, with an entity rename.",
  },
  {
    command: "add --preset <name>",
    title: "Install whole products",
    body: "Blocks that bring their own tables can sit next to yours at any time.",
  },
];

export const beforeAfter = {
  before: [
    "Write the tenancy, invitations and roles tables, then their policies.",
    "Hand-write a pipeline, a state machine and the audit triggers for each table.",
    "Wire notifications, search and a job queue yourself.",
    "Keep types in step with the schema by hand.",
    "Rework all of it when a second product needs the same parts.",
  ],
  after: [
    "Pick a preset, or add one block over a table you already have.",
    "Read the generated SQL, commit it, and change it like your own code.",
    "Run doctor to check RLS, grants and indexes before you ship.",
    "Run gen and use a typed client that returns Results.",
    "Turn features on or off per table with a tag.",
  ],
} satisfies {
  readonly before: readonly string[];
  readonly after: readonly string[];
};

export const agentTools: readonly {
  readonly title: string;
  readonly body: string;
  readonly code: string;
  readonly href: string;
}[] = [
  {
    title: "MCP server",
    body: "The CLI as an MCP server on stdio. Reads run by default, and writes wait for the user's consent.",
    code: "pnpm better-supabase mcp",
    href: "/docs/cli/mcp",
  },
  {
    title: "Agent Skills",
    body: "Four skills teach coding agents the queries, the API layer, auth and testing conventions, pinned to your version.",
    code: "pnpm better-supabase skills install",
    href: "/docs/for-ai-agents",
  },
  {
    title: "CLI agent mode",
    body: "When an agent runs the CLI, it prints one JSON envelope, never prompts, and stops before destructive work.",
    code: "pnpm better-supabase gen --agent yes",
    href: "/docs/cli/agent-mode",
  },
];
