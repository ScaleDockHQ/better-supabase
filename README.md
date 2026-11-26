# better-supabase

**A typed data layer for Supabase: generated repositories that return Results and run under RLS, auth helpers, framework adapters and a CLI.**

[![npm](https://img.shields.io/npm/v/better-supabase)](https://www.npmjs.com/package/better-supabase)
[![downloads](https://img.shields.io/npm/dw/better-supabase)](https://www.npmjs.com/package/better-supabase)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/ScaleDockHQ/better-supabase/blob/main/LICENSE)
![TypeScript](https://img.shields.io/badge/TypeScript-6%20%7C%207-3178c6.svg)

[Docs](https://bettersupabase.com/docs) · [Quickstart](https://bettersupabase.com/docs/getting-started) · [Blocks](https://bettersupabase.com/docs/blocks) · [Examples](https://bettersupabase.com/docs/examples) · [Changelog](https://bettersupabase.com/changelog) · [GitHub](https://github.com/ScaleDockHQ/better-supabase)

better-supabase sits on the supabase-js client you already use. You keep your database, your RLS policies, Supabase Auth and Storage. The CLI reads your schema and generates a typed repository for every table, so a query is a typed object instead of a string. It is an independent, MIT-licensed project built on the official Supabase packages, not a Supabase product, and the raw client stays one property away as `db.$client`.

## The same query, typed

With supabase-js, the columns and relations are a string, a filter on a related table needs `!inner` and a dotted path, and the error is a Postgres or PostgREST code:

```ts
const { data, error } = await supabase
  .from("customers")
  .select("id, name, organization(name), notes!inner(kind)")
  .eq("status", "active")
  .eq("notes.kind", "call")
  .order("name")
  .limit(20);
if (error) throw error;
```

With better-supabase, the same read is an object the compiler checks, the row type follows from `select` and `include`, and the call returns a `Result` instead of throwing:

```ts
const result = await db.customers.list({
  select: ["id", "name"],
  where: { status: "active", notes: { some: { kind: "call" } } },
  include: { organization: { select: ["name"] } },
  orderBy: { name: "asc" },
  limit: 20,
});

if (!result.ok) {
  // result.error.kind is "unauthorized", "timeout", "network" and so on
  return Response.json(result.error, { status: result.error.status });
}

result.data; // { id: string; name: string; organization: { name: string } }[]
```

It is still one PostgREST request, and it runs as the signed-in user, so your RLS policies decide what it can read. Call `.orThrow()` when you would rather throw. The [supabase-js migration guide](https://bettersupabase.com/docs/migration/supabase-js) maps every supabase-js call to its repository equivalent.

## What you get

| Feature                   | What it does                                                                                                                                                                                                            |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Stronger generated types  | [`gen`](https://bettersupabase.com/docs/cli/gen) writes the same `database.types.ts` as `supabase gen types`, and adds relationship cardinality, unique keys, CHECK-constraint unions, typed jsonb and per-table flags. |
| A typed repository        | [`list`, `get` and the writes](https://bettersupabase.com/docs/repository) take `where`, `include`, `orderBy` and pagination, and compile to one PostgREST request, or to SQL on the direct-Postgres path.              |
| Results, not exceptions   | Every call returns a [`Result`](https://bettersupabase.com/docs/concepts/results) with a plain, serializable `DbError`, safe to return from server actions and RPC handlers.                                            |
| Queries as the caller     | `connect()` runs per request with the user's client, so every query runs under their RLS policies. Rows keep [your casing](https://bettersupabase.com/docs/concepts/casing), snake_case or camelCase.                   |
| Auth without round trips  | A valid access token is [verified locally](https://bettersupabase.com/docs/auth) and never reaches the Auth server. Refresh happens once, in the proxy.                                                                 |
| Caches that follow writes | Writes invalidate the [cache tags](https://bettersupabase.com/docs/concepts/caching) of the tables they touch, and the generated [data hooks](https://bettersupabase.com/docs/frontend/data-hooks) refetch.             |
| Checks before you ship    | [`doctor`](https://bettersupabase.com/docs/cli/doctor) reports missing RLS, grants and indexes, config and env drift, and the Supabase advisors.                                                                        |
| Blocks of SQL you own     | A [block](https://bettersupabase.com/docs/blocks) renders tables, policies and functions into your repository for features most apps build by hand.                                                                     |

## Quick start

1. Install the package, and the two optional peers the CLI loads:

   ```bash
   pnpm add better-supabase @supabase/supabase-js
   pnpm add -D pg @supabase/postgrest-typegen@0.8.1
   ```

2. Write the config, `src/lib/supabase` and the glue for the frameworks it finds:

   ```bash
   pnpm better-supabase init
   ```

3. Start the local stack, write its URL and keys to `.env.local`, and generate the types:

   ```bash
   supabase start
   pnpm better-supabase dev env
   pnpm better-supabase gen
   ```

4. Define the app once, and create the server instance for your framework. On Next.js:

   ```ts title="src/lib/supabase/index.ts"
   import { createSupabase } from "better-supabase";

   import { schema } from "./generated-schema.ts";

   export const betterSupabase = createSupabase(schema);
   ```

   ```ts title="src/lib/supabase/server.ts"
   import "server-only";
   import { createNext } from "better-supabase/next";

   import { betterSupabase } from "./index";

   export const bsb = createNext(betterSupabase);
   ```

5. Query as the caller from a Server Component, route handler or server action:

   ```ts
   const { db } = await bsb.context();

   const customers = await db.customers
     .list({ where: { status: "active" }, limit: 20 })
     .orThrow();
   ```

Run `better-supabase gen --check` in CI to fail when the schema and the generated files drift apart. The [Quickstart](https://bettersupabase.com/docs/getting-started) has each step in full.

| Requirement   | Version                                                                                                                                        |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Node.js       | 24 or later for the CLI                                                                                                                        |
| Runtimes      | The runtime entries import no Node built-ins and run on every WinterTC runtime; `cli`, `node`, `nestjs`, `postgres` and `testing` need Node    |
| TypeScript    | 6 and 7, with `nodenext` or `bundler` module resolution                                                                                        |
| Module format | ESM only                                                                                                                                       |
| Peers         | `@supabase/supabase-js`; every other peer is optional and listed per subpath on [Peers](https://bettersupabase.com/docs/getting-started/peers) |

## Add it to an existing app

Every step is optional and reversible, and you can stop on any of them:

1. `better-supabase init` writes a config with no blocks and no SQL, and changes nothing in the database.
2. `better-supabase gen` types the tables you already have: repositories, validators and hooks.
3. `better-supabase table <t> enable <feature>` turns on realtime, audit, search or subjects for one table, through a tag in its comment.
4. `better-supabase add <block> --over <table>` renders a block's files over a table you own.
5. `better-supabase add --preset <name>` installs whole products next to your tables.

Old `supabase.from()` calls keep working next to the repositories, so you can move one query at a time. See [Existing apps](https://bettersupabase.com/docs/migration/existing-apps).

## Use it where you run

An adapter runs in the framework's own middleware or hook. It verifies the access token locally against the project's JWKS, which it fetches once and caches. While the token is valid it writes no cookies, and an expiring session is refreshed once, in the proxy. Every route, loader and action then gets a `db` for the caller.

| Where you run   | Adapters                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Supported       | [Next.js](https://bettersupabase.com/docs/frameworks/next), [Hono](https://bettersupabase.com/docs/frameworks/hono), [Expo Router](https://bettersupabase.com/docs/frameworks/expo), [SvelteKit](https://bettersupabase.com/docs/frameworks/sveltekit), [TanStack Start](https://bettersupabase.com/docs/frameworks/tanstack-start), [React Router](https://bettersupabase.com/docs/frameworks/react-router)                                                                                        |
| Community       | [Astro](https://bettersupabase.com/docs/frameworks/astro), [Edge Functions](https://bettersupabase.com/docs/frameworks/edge), [Elysia](https://bettersupabase.com/docs/frameworks/elysia), [H3](https://bettersupabase.com/docs/frameworks/h3), [Nuxt](https://bettersupabase.com/docs/frameworks/nuxt), [NestJS](https://bettersupabase.com/docs/frameworks/nestjs), [Node](https://bettersupabase.com/docs/frameworks/node), [SolidStart](https://bettersupabase.com/docs/frameworks/solid-start) |
| APIs and agents | [oRPC](https://bettersupabase.com/docs/frameworks/orpc), [MCP servers](https://bettersupabase.com/docs/frameworks/mcp), [WebMCP](https://bettersupabase.com/docs/frameworks/webmcp), [any other framework](https://bettersupabase.com/docs/frameworks/other)                                                                                                                                                                                                                                        |
| In the browser  | [The client](https://bettersupabase.com/docs/frontend/client), [React](https://bettersupabase.com/docs/frontend/react), [React Native](https://bettersupabase.com/docs/frontend/react-native), [Vue](https://bettersupabase.com/docs/frontend/vue), [Solid](https://bettersupabase.com/docs/frontend/solid), [Svelte](https://bettersupabase.com/docs/frontend/svelte)                                                                                                                              |
| On the device   | [PowerSync, SQLite, TanStack DB and live queries](https://bettersupabase.com/docs/frontend/local-data)                                                                                                                                                                                                                                                                                                                                                                                              |

Supported adapters get the full test matrix, an example app and every guide. Community adapters get a smoke test and a docs page, and fixes may lag. [Frameworks](https://bettersupabase.com/docs/frameworks) explains the tiers.

## The CLI

One command per job. `bsb` is the short name.

```bash
pnpm better-supabase init                    # config, client and framework glue
pnpm better-supabase gen                     # types and data hooks
pnpm better-supabase gen --check             # exit 1 in CI when the schema drifted
pnpm better-supabase table invoices enable realtime
pnpm better-supabase add queue               # a block's SQL into supabase/schemas
pnpm better-supabase add --preset crm        # every block a product needs
pnpm better-supabase doctor                  # RLS, grants, indexes and Supabase advisors
pnpm better-supabase mcp                     # the CLI as an MCP server for your coding agent
```

The [CLI reference](https://bettersupabase.com/docs/cli) lists every command and flag.

## Blocks and presets

A block is a feature most apps build by hand, such as organizations and invitations, comments, a job queue, a pipeline or invoices. `better-supabase add` renders its tables, policies and functions into files in your repository, which you review, commit and change like the rest of your schema. When the block has a TypeScript side, the app calls it on `db`.

```bash
pnpm better-supabase add comments --over public.invoices
pnpm better-supabase add --preset crm
pnpm better-supabase doctor
```

The [block catalog](https://bettersupabase.com/docs/blocks) covers organizations and identity, the database, collaboration, work, CRM, commerce, content, AI, automation, developer tools, growth, and people and scheduling. A [preset](https://bettersupabase.com/docs/presets) installs the blocks for a whole product, such as a CRM, a helpdesk or a CMS, and blocks can run [over your own tables](https://bettersupabase.com/docs/blocks/own-schemas).

## Integrations

Each integration is an optional peer, loaded only from its own subpath.

| Integration                                                         | Subpath                                                                        | What it adds                                                                                     |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| [AI SDK](https://bettersupabase.com/docs/ai-sdk)                    | `better-supabase/ai-sdk`                                                       | Stored chats as `UIMessage`s, resumable chat routes, stored agents, guardrails, usage per tenant |
| [Chat SDK](https://bettersupabase.com/docs/chat-sdk)                | `better-supabase/chat-sdk`                                                     | A Postgres state adapter and an inbox for Slack, WhatsApp and SMS                                |
| [eve](https://bettersupabase.com/docs/eve)                          | `better-supabase/eve`                                                          | eve agents on Supabase, with tools that run as the user                                          |
| [Workflow SDK](https://bettersupabase.com/docs/blocks/workflow-sdk) | `better-supabase/workflow-sdk`                                                 | A Workflow World over Postgres and Supabase Queues                                               |
| [Flags SDK](https://bettersupabase.com/docs/flags-sdk)              | `better-supabase/flags-sdk`                                                    | Flags evaluated from the flags block, per user and per tenant                                    |
| [PowerSync](https://bettersupabase.com/docs/frontend/powersync)     | `better-supabase/powersync`                                                    | The same repositories and hooks on a database on the device                                      |
| [Vercel](https://bettersupabase.com/docs/vercel)                    | `better-supabase/vercel-security`, `better-supabase/vercel-sandbox` and others | BotID, Firewall, Passport, Sandbox and the other Vercel SDKs                                     |

## Subpaths

Each feature is its own entry, so an app only loads what it imports.

| Area                                                                 | Start here                                                                                                                                                                                                                                                                                                                                                          |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repositories, results and config                                     | [`better-supabase`](https://bettersupabase.com/docs/repository)                                                                                                                                                                                                                                                                                                     |
| Validating a composed read                                           | [`better-supabase/result-schema`](https://bettersupabase.com/docs/repository/validation#validating-read-results)                                                                                                                                                                                                                                                    |
| Server, Postgres and auth                                            | [`better-supabase/server`](https://bettersupabase.com/docs/auth/server), [`better-supabase/auth`](https://bettersupabase.com/docs/auth) and [`better-supabase/postgres`](https://bettersupabase.com/docs/auth/postgres)                                                                                                                                             |
| Framework adapters                                                   | [`better-supabase/next`](https://bettersupabase.com/docs/frameworks/next), [`better-supabase/next/proxy`](https://bettersupabase.com/docs/frameworks/next#a-smaller-proxy-bundle), [`better-supabase/next/auth-gate`](https://bettersupabase.com/docs/frameworks/next#the-signed-in-user-and-authgate) and [the others](https://bettersupabase.com/docs/frameworks) |
| Browser client and data hooks                                        | [`better-supabase/client`](https://bettersupabase.com/docs/frontend/client)                                                                                                                                                                                                                                                                                         |
| Storage paths and uploads in the browser                             | [`better-supabase/storage/client`](https://bettersupabase.com/docs/platform/storage#client-only-buckets)                                                                                                                                                                                                                                                            |
| List pages, CSV downloads, date buckets and free sorts               | [`better-supabase/list`](https://bettersupabase.com/docs/platform/list), with `list/export`, `list/buckets` and `list/order`                                                                                                                                                                                                                                        |
| Blocks                                                               | [`better-supabase/blocks/<name>`](https://bettersupabase.com/docs/blocks)                                                                                                                                                                                                                                                                                           |
| APIs (OpenAPI, AsyncAPI, Arazzo)                                     | [`better-supabase/spec`](https://bettersupabase.com/docs/specs)                                                                                                                                                                                                                                                                                                     |
| Integrations                                                         | [Integrations](https://bettersupabase.com/docs/integrations)                                                                                                                                                                                                                                                                                                        |
| Authorization library adapters                                       | [`better-supabase/claims`](https://bettersupabase.com/docs/extending/authorization-providers) and [`better-supabase/contract`](https://bettersupabase.com/docs/extending/authorizers)                                                                                                                                                                               |
| Tests                                                                | [`better-supabase/testing`](https://bettersupabase.com/docs/testing)                                                                                                                                                                                                                                                                                                |
| Import text, phones, IBANs and addresses                             | [`better-supabase/normalize`](https://bettersupabase.com/docs/concepts/normalize)                                                                                                                                                                                                                                                                                   |
| Postgres cache for Next.js `cacheHandlers` and the Astro route cache | [`better-supabase/cache-postgres`](https://bettersupabase.com/docs/concepts/cache-postgres)                                                                                                                                                                                                                                                                         |
| UBL e-invoices for Peppol                                            | [`better-supabase/e-invoicing`](https://bettersupabase.com/docs/concepts/e-invoicing)                                                                                                                                                                                                                                                                               |
| Audit files (SAF-T, XAF)                                             | [`better-supabase/audit-files`](https://bettersupabase.com/docs/concepts/audit-files)                                                                                                                                                                                                                                                                               |
| FHIR R4 resources for care records                                   | [`better-supabase/fhir`](https://bettersupabase.com/docs/concepts/fhir)                                                                                                                                                                                                                                                                                             |
| Verifiable credentials (SD-JWT VC, OpenID4VCI, OpenID4VP)            | [`better-supabase/verifiable-credentials`](https://bettersupabase.com/docs/concepts/verifiable-credentials)                                                                                                                                                                                                                                                         |

## For AI agents

The package ships [Agent Skills](https://agentskills.io) for queries, APIs, auth and tests. Install the ones that match your installed version with the CLI, or the latest with the `skills` CLI:

```bash
pnpm better-supabase skills install
npx skills add ScaleDockHQ/better-supabase
```

`better-supabase mcp` serves the CLI to a coding agent over stdio: reads run by default, and writes wait for the user's consent. When an agent runs the CLI, it prints one JSON envelope, never prompts, and stops before destructive work ([agent mode](https://bettersupabase.com/docs/cli/agent-mode)). The docs are also available as [`/llms.txt`](https://bettersupabase.com/llms.txt), as Markdown at `/docs/<page>.md`, and through the read-only docs MCP server at `https://bettersupabase.com/mcp`. See [For AI agents](https://bettersupabase.com/docs/for-ai-agents).

## Limits

- PostgREST runs each request in its own transaction. Put multi-step writes in a database function and call it with `db.$rpc()`, or use `postgres.transaction()` on the direct-Postgres path.
- `gen` needs a database to read, local or hosted. It can't infer types from migrations alone, so commit the generated files and run `gen --check` in CI.
- It is not an ORM that bypasses PostgREST and RLS. Queries run as the caller, and your policies decide.
- It does not replace supabase-js or the Supabase CLI; it runs on both.

[Limitations](https://bettersupabase.com/docs/guides/limitations) covers the rest.

## Status and upgrades

better-supabase follows semver. Until 1.0, breaking changes ship in minor versions and are called out in the [changelog](https://bettersupabase.com/changelog). A deprecated API is marked `@deprecated` with its replacement and keeps working for at least one minor release. Each breaking release has an [upgrade guide](https://bettersupabase.com/docs/migration), and [`better-supabase codemod`](https://bettersupabase.com/docs/cli/codemod) rewrites renamed imports, subpaths and environment names. [Stability](https://bettersupabase.com/docs/extending/stability) defines the public API.

## Support

Report bugs and ask questions in [GitHub issues](https://github.com/ScaleDockHQ/better-supabase/issues). Report vulnerabilities privately, as described in the [security policy](https://github.com/ScaleDockHQ/better-supabase/blob/main/SECURITY.md).

## License

[MIT](https://github.com/ScaleDockHQ/better-supabase/blob/main/LICENSE) © 2026 ScaleDock

## Contributing

Setup, the local stack, scripts and the release process are in [`CONTRIBUTING.md`](./CONTRIBUTING.md). The invariants and the "when you change X, also update Y" table for anyone changing the code, human or agent, are in [`AGENTS.md`](./AGENTS.md). Every user-visible change needs a changeset.

## Repository

```
packages/better-supabase/  the library, its CLI and the consumer skills
apps/docs/                 the documentation site
apps/examples/             one app per adapter
supabase/                  the local stack and the fixture schema
```

`pnpm verify` is the gate before a push. The apps are served with `pnpm dev:portless`.
