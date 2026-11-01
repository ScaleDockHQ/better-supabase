# better-supabase

**Typed repositories, auth glue and a CLI for Supabase apps, APIs, MCP servers and jobs.**

[![npm](https://img.shields.io/npm/v/better-supabase)](https://www.npmjs.com/package/better-supabase)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/ScaleDockHQ/better-supabase/blob/main/LICENSE)
![TypeScript](https://img.shields.io/badge/TypeScript-6%20%7C%207-3178c6.svg)

[Docs](https://bettersupabase.com/docs) · [Quickstart](https://bettersupabase.com/docs/getting-started) · [Blocks](https://bettersupabase.com/docs/blocks) · [Examples](https://bettersupabase.com/docs/examples) · [Changelog](https://bettersupabase.com/changelog) · [GitHub](https://github.com/ScaleDockHQ/better-supabase)

better-supabase sits on the supabase-js client you already use. You keep your database, your RLS policies, Supabase Auth and Storage. The CLI reads your schema and generates a typed repository for every table, so a query is a typed object instead of a string.

## Before and after

With supabase-js, the query is a string and the error is a Postgres code:

```ts
const { data, error } = await supabase
  .from("customers")
  .select("id, name")
  .eq("status", "active")
  .limit(20);
if (error) throw error;
```

With better-supabase, the same read is a typed call on `db`, and the generated hook takes the same arguments:

```ts
const customers = await db.customers
  .list({ select: ["id", "name"], where: { status: "active" }, limit: 20 })
  .orThrow();

const rows = useCustomers({
  select: ["id", "name"],
  where: { status: "active" },
  limit: 20,
});
```

Each call is still one PostgREST request, and it runs as the signed-in user, so your RLS policies decide what it can read and write. The [supabase-js migration guide](https://bettersupabase.com/docs/migration/supabase-js) maps every supabase-js call to its repository equivalent.

## Install and quick start

```bash
pnpm add better-supabase @supabase/supabase-js
pnpm add -D pg @supabase/postgrest-typegen@0.6.0

supabase start
pnpm better-supabase init    # config, src/lib/supabase and framework glue
pnpm better-supabase gen     # database.types.ts, generated.ts and the data hooks
```

`pg` and `@supabase/postgrest-typegen` are optional peers that only the CLI loads. The package is ESM only. The CLI needs Node 24 or later, and the runtime entries run on every WinterTC runtime.

On the server, the adapter gives each request a `db` for the caller. In the browser, `bsb.db` is the same client for the current session:

```ts
const { db } = await bsb.context();

const customers = await db.customers
  .list({ where: { status: "active" }, limit: 20 })
  .orThrow();
```

`gen.hooks` writes `useCustomers` and `useCustomer` next to the generated module. [Data hooks](https://bettersupabase.com/docs/frontend/data-hooks) covers the options.

## Use it where you run

An adapter verifies the session, refreshes it in the proxy and gives each handler a `db` for the caller.

| Where you run                                                             | Docs                                                              |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Next.js, Hono, oRPC, Expo Router, SvelteKit, TanStack Start, React Router | [Frameworks](https://bettersupabase.com/docs/frameworks)          |
| Edge Functions, Node, NestJS, Astro, SolidStart, H3, Nuxt, Elysia         | [Frameworks](https://bettersupabase.com/docs/frameworks)          |
| React, React Native, Vue, Solid, Svelte                                   | [Frontend](https://bettersupabase.com/docs/frontend/client)       |
| PowerSync and SQLite on the device                                        | [Local data](https://bettersupabase.com/docs/frontend/local-data) |
| MCP servers                                                               | [MCP](https://bettersupabase.com/docs/frameworks/mcp)             |
| Page tools for browser agents (WebMCP)                                    | [WebMCP](https://bettersupabase.com/docs/frameworks/webmcp)       |

## The CLI

One command per job. `bsb` is the short name.

```bash
pnpm better-supabase init            # config, client and framework glue
pnpm better-supabase gen             # types and data hooks
pnpm better-supabase gen --check     # exit 1 in CI when the schema drifted
pnpm better-supabase add queue       # a block's SQL into supabase/schemas
pnpm better-supabase doctor          # RLS, grants, indexes and Supabase advisors
pnpm better-supabase skills install  # Agent Skills for your coding agent
```

The [CLI reference](https://bettersupabase.com/docs/cli) lists every command and flag.

## Blocks and presets

A block is a feature most apps build by hand. `better-supabase add` installs its SQL, and the app calls the instance on `db`. The catalog is grouped by what the block is for:

| Category                   | Catalog                                                                       |
| -------------------------- | ----------------------------------------------------------------------------- |
| Organizations and identity | [Organizations](https://bettersupabase.com/docs/blocks/catalog-organizations) |
| Database                   | [Database](https://bettersupabase.com/docs/blocks/catalog-database)           |
| Collaboration              | [Collaboration](https://bettersupabase.com/docs/blocks/catalog-collaboration) |
| Work                       | [Work](https://bettersupabase.com/docs/blocks/catalog-work)                   |
| CRM                        | [CRM](https://bettersupabase.com/docs/blocks/catalog-crm)                     |
| Commerce                   | [Commerce](https://bettersupabase.com/docs/blocks/catalog-commerce)           |
| Content                    | [Content](https://bettersupabase.com/docs/blocks/catalog-content)             |
| AI                         | [AI](https://bettersupabase.com/docs/blocks/catalog-ai)                       |
| Automation                 | [Automation](https://bettersupabase.com/docs/blocks/catalog-automation)       |
| Developer                  | [Developer](https://bettersupabase.com/docs/blocks/catalog-developer)         |
| Growth                     | [Growth](https://bettersupabase.com/docs/blocks/catalog-growth)               |
| People and scheduling      | [People](https://bettersupabase.com/docs/blocks/catalog-people)               |

A [preset](https://bettersupabase.com/docs/presets) installs a set of blocks for a product, such as a CRM, a helpdesk or a CMS.

## Subpaths

Each feature is its own entry, so an app only loads what it imports.

| Area                                    | Start here                                                                                                                                                                            |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repositories, results and config        | [`better-supabase`](https://bettersupabase.com/docs/repository)                                                                                                                       |
| Server, Postgres and auth               | [`better-supabase/server`](https://bettersupabase.com/docs/auth/server)                                                                                                               |
| Framework adapters                      | [`better-supabase/next`](https://bettersupabase.com/docs/frameworks)                                                                                                                  |
| Browser client and data hooks           | [`better-supabase/client`](https://bettersupabase.com/docs/frontend/client)                                                                                                           |
| Blocks                                  | [`better-supabase/blocks/<name>`](https://bettersupabase.com/docs/blocks)                                                                                                             |
| APIs (OpenAPI, AsyncAPI, Arazzo)        | [`better-supabase/spec`](https://bettersupabase.com/docs/specs)                                                                                                                       |
| FHIR R4 resources for care records      | [`better-supabase/fhir`](https://bettersupabase.com/docs/concepts/fhir)                                                                                                               |
| UBL e-invoices for Peppol               | [`better-supabase/e-invoicing`](https://bettersupabase.com/docs/concepts/e-invoicing)                                                                                                 |
| Audit files (SAF-T, XAF)                | [`better-supabase/audit-files`](https://bettersupabase.com/docs/concepts/audit-files)                                                                                                 |
| AI SDK, Chat SDK, eve, flags, workflows | [Integrations](https://bettersupabase.com/docs/integrations)                                                                                                                          |
| Authorization library adapters          | [`better-supabase/claims`](https://bettersupabase.com/docs/extending/authorization-providers) and [`better-supabase/contract`](https://bettersupabase.com/docs/extending/authorizers) |
| Tests                                   | [`better-supabase/testing`](https://bettersupabase.com/docs/testing)                                                                                                                  |

## For AI agents

The package ships [Agent Skills](https://agentskills.io) for queries, APIs, auth and tests:

```bash
npx skills add ScaleDockHQ/better-supabase
```

The docs are also available as [`/llms.txt`](https://bettersupabase.com/llms.txt), as Markdown at `/docs/<page>.md`, and through the read-only docs MCP server at `https://bettersupabase.com/mcp`. See [For AI agents](https://bettersupabase.com/docs/for-ai-agents).

## Documentation

The full documentation is at [bettersupabase.com/docs](https://bettersupabase.com/docs).

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

## Security

Report vulnerabilities privately; see [`SECURITY.md`](./SECURITY.md).
