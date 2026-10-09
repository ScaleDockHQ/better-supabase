# better-supabase

**Typed repositories, auth glue and a CLI for Supabase apps, APIs, MCP servers and jobs.**

[![npm](https://img.shields.io/npm/v/better-supabase)](https://www.npmjs.com/package/better-supabase)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
![TypeScript](https://img.shields.io/badge/TypeScript-6%20%7C%207-3178c6.svg)
[![CI](https://img.shields.io/github/actions/workflow/status/ScaleDockHQ/better-supabase/ci.yml?label=CI)](https://github.com/ScaleDockHQ/better-supabase/actions/workflows/ci.yml)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](./CODE_OF_CONDUCT.md)

[Docs](https://bettersupabase.com/docs) · [Quickstart](https://bettersupabase.com/docs/getting-started) · [Examples](https://bettersupabase.com/docs/examples) · [Changelog](https://bettersupabase.com/changelog) · [npm](https://www.npmjs.com/package/better-supabase)

better-supabase sits on top of the supabase-js client you already use. You keep your database, your RLS policies, Supabase Auth and Storage. The CLI reads your schema and generates a typed repository for every table, so a query is a typed object instead of a string, a typo in a column name is a compile error, and the row type follows what you selected.

It also writes the glue every Supabase app repeats: the session cookie and token refresh for Next.js, Hono, oRPC, Edge Functions, MCP servers and [every other supported framework](https://bettersupabase.com/docs/frameworks), pagination, soft delete, timestamps, cache invalidation, background jobs and typed Storage and Realtime. It is built on [`@supabase/supabase-js`](https://github.com/supabase/supabase-js), [`@supabase/server`](https://github.com/supabase/server), [`@supabase/middleware`](https://github.com/supabase/middleware) and [`@supabase/ssr`](https://github.com/supabase/ssr). It is an independent open-source project, not made by Supabase.

## Before and after

With supabase-js, the query is a string and the error is a Postgres code:

```ts
const { data, error } = await supabase
  .from("customers")
  .select("id, name, organization(name), notes!inner(kind)")
  .eq("status", "active")
  .eq("notes.kind", "call")
  .order("name")
  .limit(20);
if (error) throw error;

const { error: insertError } = await supabase.from("tags").insert({ name });
if (insertError?.code === "23505") return { message: "Tag already exists" };
```

With better-supabase, every column, relation and operator is typed, and errors are values with a `kind`:

```ts
const customers = await db.customers.findMany({
  select: ["id", "name"],
  where: { status: "active", notes: { some: { kind: "call" } } },
  include: { organization: { select: ["name"] } },
  orderBy: { name: "asc" },
  limit: 20,
});
// customers.data: { id: string; name: string; organization: { name: string } }[]

const tag = await db.tags.create({ organizationId, name });
if (tag.error?.kind === "conflict") return { message: "Tag already exists" };
```

Each call is still one PostgREST request, and it runs as the signed-in user, so your RLS policies decide what it can read and write. The [supabase-js migration guide](https://bettersupabase.com/docs/migration/supabase-js) maps every supabase-js call to its repository equivalent, and the two work side by side while you move over.

## What you get

- **Stronger generated types.** [`better-supabase gen`](https://bettersupabase.com/docs/cli/gen) writes the same `database.types.ts` as `supabase gen types` and adds relationship cardinality, unique keys, CHECK-constraint unions, typed jsonb and camelCase column maps.
- **A typed repository per table.** [`findMany`, `findUnique`, `create`, `upsert`, `paginate`, counts and aggregates](https://bettersupabase.com/docs/repository), with nested relation filters and includes, compiled to PostgREST or to SQL on a direct Postgres connection.
- **Results instead of exceptions.** Every call returns a [`Result` with a plain, serializable `DbError`](https://bettersupabase.com/docs/concepts/results) that you can return from server actions and RPC handlers. `.orThrow()` is opt-in, and adapters turn errors into RFC 9457 Problem Details with the right status.
- **Your casing.** Keep database names with `casing: 'snake'`, or get [camelCase rows](https://bettersupabase.com/docs/concepts/casing) renamed inside the PostgREST query.
- **Auth without extra round trips.** Valid access tokens are [verified locally](https://bettersupabase.com/docs/auth) against the JWKS and never reach the Auth server. Refresh happens once, in the proxy. The service role is an explicit `bs.admin()` call.
- **Cache tags that follow writes.** Mutations [invalidate the tables they change](https://bettersupabase.com/docs/concepts/caching), with read-your-writes in Next.js server actions and table-based invalidation in TanStack Query.
- **Plugins.** [Timestamps, soft delete, tenant scoping, actor columns, validation and rules](https://bettersupabase.com/docs/plugins), each versioned and opt-in.
- **Blocks for the SQL every app repeats.** [Jobs on Supabase Queues](https://bettersupabase.com/docs/blocks/jobs), webhook inboxes, idempotency keys, organizations and invitations, notifications, outgoing webhooks, API keys, billing, usage quotas, feature flags, SSO and SCIM, vector search and Stripe entitlements. [`better-supabase sql add`](https://bettersupabase.com/docs/blocks/sql) writes the tables, functions and policies into your declarative schema.
- **Tests and CI checks.** [`asUser`](https://bettersupabase.com/docs/testing) runs RLS tests as any user against the local stack, `gen --check` fails on schema drift, and [`doctor`](https://bettersupabase.com/docs/cli/doctor) reports security and performance findings, with SARIF output for code scanning.

## Install

```bash
pnpm add better-supabase @supabase/supabase-js
pnpm add -D pg
```

Before installing, `npx better-supabase init` detects your frameworks and prints the install command for your package manager. The package is ESM only. The CLI needs Node 24 or later, and the runtime entries run on every WinterTC runtime. On runtimes without a native `Temporal` (Node 24, Safari), load [`temporal-polyfill`](https://bettersupabase.com/docs/concepts/temporal) once at startup. TypeScript 6 and 7 are tested.

## Quick start

Generate the typed schema from your local stack:

```bash
supabase start
pnpm better-supabase init   # config, src/lib/supabase/index.ts and framework glue
pnpm better-supabase env    # URL and keys into .env.local
pnpm better-supabase gen    # database.types.ts and generated.ts
```

Define the client once, then connect it per request with the current user's Supabase client:

```ts
import { createClient } from "@supabase/supabase-js";
import { defineSupabase } from "better-supabase";

import { schema } from "./lib/supabase/generated.ts";

export const betterSupabase = defineSupabase(schema);

const db = betterSupabase.connect(createClient(url, publishableKey));

const customers = await db.customers
  .findMany({ select: ["id", "name"], where: { status: "active" } })
  .orThrow();
```

`defineSupabase` holds no secrets and no connection. Because you connect with the client for the current user, every query runs under their RLS policies.

## Use it where you run

An adapter verifies the session, refreshes it where it should and gives each handler a `db` for the caller. In Next.js:

```tsx
// src/lib/supabase/server.ts
export const bs = createNext(betterSupabase);

// src/proxy.ts
export const proxy = (request: NextRequest) => bs.proxy(request);

// app/customers/page.tsx
export default async function Customers() {
  const { db } = await bs.context();
  const customers = await db.customers
    .findMany({ select: ["id", "name"] })
    .orThrow();
  return <CustomerList customers={customers} />;
}
```

| Where you run                      | What the adapter gives you                                                 | Docs                                                                                                                                                                    |
| ---------------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Next.js                            | Proxy, Server Components, route handlers, server actions and cache tags    | [Next.js](https://bettersupabase.com/docs/frameworks/next)                                                                                                              |
| Hono                               | Middleware, Result-aware handlers and REST resources that match OpenAPI    | [Hono](https://bettersupabase.com/docs/frameworks/hono)                                                                                                                 |
| oRPC                               | A middleware that adds the caller's repositories to the oRPC context       | [oRPC](https://bettersupabase.com/docs/frameworks/orpc)                                                                                                                 |
| Edge Functions, Deno, Bun, Workers | Fetch handlers with the caller's repositories                              | [Edge](https://bettersupabase.com/docs/frameworks/edge)                                                                                                                 |
| Expo Router                        | Server loaders, API routes and middleware that run as the caller           | [Expo Router](https://bettersupabase.com/docs/frameworks/expo)                                                                                                          |
| TanStack Start                     | Request middleware with the caller's repositories in every server function | [TanStack Start](https://bettersupabase.com/docs/frameworks/tanstack-start)                                                                                             |
| SvelteKit                          | A `handle` hook with the caller's repositories on `event.locals`           | [SvelteKit](https://bettersupabase.com/docs/frameworks/sveltekit)                                                                                                       |
| React Router                       | Server middleware with the caller's repositories in loaders and actions    | [React Router](https://bettersupabase.com/docs/frameworks/react-router)                                                                                                 |
| H3, Nitro and Nuxt                 | H3 2 middleware, Nitro 2 middleware and a Nuxt module                      | [H3](https://bettersupabase.com/docs/frameworks/h3), [Nuxt](https://bettersupabase.com/docs/frameworks/nuxt)                                                            |
| Elysia                             | The caller's repositories derived into every route                         | [Elysia](https://bettersupabase.com/docs/frameworks/elysia)                                                                                                             |
| Node, Express, Fastify, Koa        | Middleware with route guards and Problem Details errors                    | [Node](https://bettersupabase.com/docs/frameworks/node)                                                                                                                 |
| NestJS                             | Middleware, `@Ctx()` and role guards                                       | [NestJS](https://bettersupabase.com/docs/frameworks/nestjs)                                                                                                             |
| Astro and SolidStart               | Middleware, page guards and actions                                        | [Astro](https://bettersupabase.com/docs/frameworks/astro), [SolidStart](https://bettersupabase.com/docs/frameworks/solid-start)                                         |
| MCP servers                        | Tools from your tables and your own code, running as the signed-in user    | [MCP](https://bettersupabase.com/docs/frameworks/mcp)                                                                                                                   |
| React and TanStack Query           | A browser client, typed hooks, query and mutation options, live queries    | [Frontend](https://bettersupabase.com/docs/frontend/query)                                                                                                              |
| Vue, Solid and Svelte              | Live queries, presence, actions and the session                            | [Vue](https://bettersupabase.com/docs/frontend/vue), [Solid](https://bettersupabase.com/docs/frontend/solid), [Svelte](https://bettersupabase.com/docs/frontend/svelte) |

Every adapter is listed on the [frameworks overview](https://bettersupabase.com/docs/frameworks).

## The CLI

The `better-supabase` command ships in this package:

```bash
pnpm better-supabase init                   # config, client and framework glue
pnpm better-supabase env                    # local URL and keys into .env.local
pnpm better-supabase gen                    # database.types.ts and generated.ts
pnpm better-supabase gen --check            # exit 1 in CI when the schema drifted
pnpm better-supabase doctor                 # RLS, grants, indexes and Supabase advisors
pnpm better-supabase doctor --format sarif  # the same findings for GitHub code scanning
pnpm better-supabase sql add jobs           # a SQL module into supabase/schemas
pnpm better-supabase skills install         # Agent Skills for your coding agent
```

See the [CLI reference](https://bettersupabase.com/docs/cli) for every command and flag.

## Blocks

Blocks are the features most SaaS apps build by hand. Each one installs [SQL modules](https://bettersupabase.com/docs/blocks/sql) (tables, functions and RLS policies) into your declarative schema, and blocks with a TypeScript side import it from `better-supabase/blocks/<name>`:

```bash
pnpm better-supabase sql add organizations invitations
```

List them in `sql.modules` in `better-supabase.config.ts` so `better-supabase sql sync` keeps the files up to date. Each key is a module, and its value holds that module's settings, such as its roles, permission keys or the existing tables it adopts:

```ts
export default defineConfig({
  sql: {
    modules: {
      access: {
        roles: {
          owner: ["*"],
          admin: ["organization.*", "members.*"],
          member: ["organization.read"],
        },
      },
      organizations: {},
      invitations: { permissions: { invite: "organization.members.invite" } },
    },
  },
});
```

The TypeScript side calls those functions as the signed-in user:

```ts
import { createOrganizations } from "better-supabase/blocks/organizations";

const organizations = createOrganizations({ transport, actorId: user.id });
await organizations.invite({ organizationId, email, role: "member" });
```

| Block                                                                                                                                                                                   | Import                                                                                     | SQL modules                            |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------- |
| [createBlocks](https://bettersupabase.com/docs/blocks/create-blocks): builds several blocks from one set of options and wires the blocks that use each other                            | `better-supabase/blocks`                                                                   | none                                   |
| [Access contract](https://bettersupabase.com/docs/blocks/access): `can()` for policies, over fixed roles, your own permission catalog or an authorization provider                      | SQL only                                                                                   | `access`, `tenant`                     |
| [Organizations](https://bettersupabase.com/docs/blocks/organizations): members, invitations, roles and switching                                                                        | `better-supabase/blocks/organizations`                                                     | `organizations`, `invitations`         |
| [Profiles](https://bettersupabase.com/docs/blocks/profiles): a profile row per user, synced from Auth                                                                                   | `better-supabase/blocks/profiles`                                                          | `profiles`                             |
| [Jobs](https://bettersupabase.com/docs/blocks/jobs): Supabase Queues jobs, cron, idempotency keys and a webhook inbox                                                                   | `better-supabase/blocks/jobs`                                                              | `jobs`, `idempotency`, `webhook-inbox` |
| [Outbox](https://bettersupabase.com/docs/blocks/outbox): transactional events with consumer cursors, relayed as CloudEvents                                                             | `better-supabase/blocks/outbox`                                                            | `outbox`                               |
| [Notifications](https://bettersupabase.com/docs/blocks/notifications): sending, listing and delivering notifications, and `useNotifications` for a live list                            | `better-supabase/blocks/notifications`, `better-supabase/blocks/notifications/react`       | `notifications`                        |
| [Inbox](https://bettersupabase.com/docs/blocks/inbox): shared inboxes with conversations, assignment, notes, read receipts and channel delivery, plus `useInbox` and a chat widget      | `better-supabase/blocks/inbox`, `better-supabase/blocks/inbox/react`                       | `inbox`, `chat-sdk-state`              |
| [Webhooks](https://bettersupabase.com/docs/blocks/webhooks-out): Standard Webhooks, verifying incoming ones and delivering outgoing ones                                                | `better-supabase/blocks/webhooks`                                                          | `webhooks-out`                         |
| [API keys](https://bettersupabase.com/docs/blocks/api-keys): hashed keys per tenant and per user, with scopes, rotation, expiry and an `apiKey` caller in every adapter                 | `better-supabase/blocks/api-keys`                                                          | `api-keys`                             |
| [Audit log](https://bettersupabase.com/docs/blocks/audit): list, filter, export as NDJSON or OCSF, and purge per tenant                                                                 | `better-supabase/blocks/audit`                                                             | `audit`                                |
| [Settings](https://bettersupabase.com/docs/blocks/settings): typed settings per user and per organization, validated with Standard Schema                                               | `better-supabase/blocks/settings`                                                          | `settings`                             |
| [Usage](https://bettersupabase.com/docs/blocks/usage): idempotent usage counters, quotas in RLS and RPCs, and Stripe meter reporting                                                    | `better-supabase/blocks/usage`                                                             | `usage`                                |
| [Billing](https://bettersupabase.com/docs/blocks/billing): Stripe Checkout, the customer portal, seat sync and webhook handling                                                         | `better-supabase/blocks/billing`                                                           | `billing`                              |
| [Feature flags](https://bettersupabase.com/docs/blocks/flags): targeting rules, overrides and rollouts, evaluated in RLS and in an OpenFeature-shaped provider                          | `better-supabase/blocks/flags`                                                             | `flags`                                |
| [Comments](https://bettersupabase.com/docs/blocks/comments): threaded comments with mentions, and an activity feed from the outbox                                                      | `better-supabase/blocks/comments`                                                          | `comments`                             |
| [Attachments](https://bettersupabase.com/docs/blocks/attachments): files linked to records, signed uploads and downloads, and a malware scan gate                                       | `better-supabase/blocks/attachments`                                                       | `attachments`                          |
| [Data lifecycle](https://bettersupabase.com/docs/blocks/data-lifecycle): data exports and organization deletion with a grace period                                                     | `better-supabase/blocks/data-lifecycle`                                                    | `data-lifecycle`                       |
| [SSO](https://bettersupabase.com/docs/blocks/sso): verified domains, SAML per organization, SSO enforcement and SCIM 2.0                                                                | `better-supabase/blocks/sso`                                                               | `sso`                                  |
| [Onboarding](https://bettersupabase.com/docs/blocks/onboarding): checklists per user or organization, and `useOnboarding`                                                               | `better-supabase/blocks/onboarding`, `better-supabase/blocks/onboarding/react`             | `onboarding`                           |
| [Waitlist](https://bettersupabase.com/docs/blocks/waitlist): a waitlist with approvals, hashed invite codes and an invite-only sign-up hook                                             | `better-supabase/blocks/waitlist`                                                          | `waitlist`                             |
| [Announcements](https://bettersupabase.com/docs/blocks/announcements): in-app announcements by audience and time window, and `useAnnouncements`                                         | `better-supabase/blocks/announcements`, `better-supabase/blocks/announcements/react`       | `announcements`                        |
| [AI chat](https://bettersupabase.com/docs/blocks/ai-chat): chats with branches, shares, a model catalog, moderation and runs, in the canonical message format, and `useAiChats`         | `better-supabase/blocks/ai-chat`, `better-supabase/blocks/ai-chat/react`                   | `ai-chat`                              |
| [AI files](https://bettersupabase.com/docs/blocks/ai-files): attachments and generated files in a private bucket, provider file references and versioned documents with suggested edits | `better-supabase/blocks/ai-files`                                                          | `ai-files`                             |
| [Knowledge](https://bettersupabase.com/docs/blocks/knowledge): documents chunked and embedded per organization, user, agent or chat, and hybrid search                                  | `better-supabase/blocks/knowledge`                                                         | `knowledge`                            |
| [Memory](https://bettersupabase.com/docs/blocks/memory): memory files, archival facts and message recall per user, agent or chat                                                        | `better-supabase/blocks/memory`                                                            | `memory`                               |
| [Agents](https://bettersupabase.com/docs/blocks/agents): custom assistants with instructions, tools, knowledge and starters, a gallery with installs and ratings                        | `better-supabase/blocks/agents`                                                            | `agents`                               |
| [Connectors](https://bettersupabase.com/docs/blocks/connectors): MCP servers per organization, per-user grants behind a `credential_ref`, sessions and tool fingerprints                | `better-supabase/blocks/connectors`                                                        | `connectors`                           |
| [AI tasks](https://bettersupabase.com/docs/blocks/ai-tasks): scheduled prompts that run an agent on a cron and record each run                                                          | `better-supabase/blocks/ai-tasks`                                                          | `ai-tasks`                             |
| [Push notifications](https://bettersupabase.com/docs/blocks/push): device tokens with RLS, Expo registration and an Expo Push API sender                                                | `better-supabase/blocks/push`                                                              | `push`                                 |
| [AI cache](https://bettersupabase.com/docs/blocks/ai-cache): model responses cached by key with a capped TTL and a purge job                                                            | `better-supabase/blocks/ai-cache`                                                          | `ai-cache`                             |
| [AI providers](https://bettersupabase.com/docs/blocks/ai-providers): per-tenant provider keys as credential refs, batch jobs and sandboxes with an idle stop                            | `better-supabase/blocks/ai-providers`                                                      | `ai-providers`                         |
| [Workflows](https://bettersupabase.com/docs/blocks/workflows): a run registry for any engine, schedules, semaphores, admission control, and `useWorkflowRuns`                           | `better-supabase/blocks/workflows`, `better-supabase/blocks/workflows/react`               | `workflows`, `workflow-sdk-world`      |
| [Workflow builder](https://bettersupabase.com/docs/blocks/workflow-builder): graph workflows members edit and publish, triggers, credentials, node run status and alerts                | `better-supabase/blocks/workflow-builder`, `better-supabase/blocks/workflow-builder/react` | `workflow-builder`                     |
| [Entitlements](https://bettersupabase.com/docs/blocks/entitlements): Stripe entitlements per tenant, `hasEntitlement` and the members of a plan change                                  | `better-supabase/blocks/entitlements`                                                      | `entitlements`                         |
| [Vector search](https://bettersupabase.com/docs/blocks/vector-search): `search_<table>` functions over embedding columns, called with `db.$search`                                      | SQL only                                                                                   | `vector-search`                        |

The other SQL modules (`updated-at`, `actor`, `rate-limit`, `support-sessions` and the rest) are listed on the [SQL modules page](https://bettersupabase.com/docs/blocks/sql), and the [roadmap](https://bettersupabase.com/docs/roadmap) lists what comes next.

## Works with

| Area       | Supported                                                                                                                                                                                                            |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Frameworks | Next.js 16, Hono, oRPC, Expo Router, TanStack Start, SvelteKit, React Router, H3 and Nitro, Nuxt, Elysia, Node (`node:http`, Express, Fastify, Koa), NestJS, Astro, SolidStart, Supabase Edge Functions, MCP servers |
| Runtimes   | Node.js, Deno, Bun, Cloudflare Workers, Vercel Functions, Supabase Edge                                                                                                                                              |
| Frontend   | React 19, React Native and Expo, Vue, Solid, Svelte 5, TanStack Query 5, TanStack DB, live queries over Realtime                                                                                                     |
| Local data | PowerSync, expo-sqlite                                                                                                                                                                                               |
| AI         | AI SDK, Chat SDK, eve, Workflow SDK, MCP                                                                                                                                                                             |
| Validation | Zod, Valibot and any Standard Schema                                                                                                                                                                                 |
| Standards  | OpenAPI 3.1, RFC 9457, OpenTelemetry, CloudEvents, Standard Webhooks, MCP                                                                                                                                            |
| Testing    | Vitest, pgTAP, the Supabase local stack                                                                                                                                                                              |

## Good to know

- **It does not replace supabase-js.** Auth flows, Storage and Realtime stay on the supabase-js client, which is one property away as `db.$client`.
- **It does not replace RLS.** Queries run as the caller and your policies decide. Bypassing them takes an explicit `bs.admin()`.
- **A direct Postgres connection is optional.** Queries go through PostgREST by default. [`better-supabase/postgres`](https://bettersupabase.com/docs/auth/postgres) runs the same repository API over SQL for jobs, scripts and transactions.
- **PostgREST's limits still apply.** There are no transactions across requests, and a few filters only work on reads. The [limitations page](https://bettersupabase.com/docs/guides/limitations) lists each one and what to use instead.

## Subpaths

The package has one entry per feature, so an app only loads what it imports. Every subpath is listed below, grouped by area. In a cell with several imports, `/name` is short for `better-supabase/name`.

### Core

| Import                                                                                                                                     | What it gives you                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `better-supabase`                                                                                                                          | `defineSupabase`, repositories, `Result`, `DbError`, `SPEC_PINS`                     |
| `better-supabase/config`                                                                                                                   | `defineConfig` and generators for `better-supabase.config.ts`                        |
| `better-supabase/server`                                                                                                                   | Repositories bound to the caller, admin and acting-as identities                     |
| `better-supabase/postgres`                                                                                                                 | The same repositories over direct Postgres                                           |
| `better-supabase/env`                                                                                                                      | Validated Supabase settings                                                          |
| `better-supabase/list`                                                                                                                     | Search, facets, sorting and pagination from one definition                           |
| `better-supabase/storage`, `/realtime`                                                                                                     | Typed buckets (paths, versions, vector, analytics) and broadcast topics              |
| `better-supabase/plugins/timestamps`, `/plugins/soft-delete`, `/plugins/tenant`, `/plugins/actor`, `/plugins/validation`, `/plugins/rules` | Timestamps, soft delete, tenant scoping, actor columns, validation and runtime rules |
| `better-supabase/sql`                                                                                                                      | The SQL modules and read-set compiler behind `better-supabase sql`                   |
| `better-supabase/lint`                                                                                                                     | Editor rules for unbounded reads and unscoped deletes                                |
| `better-supabase/cli`                                                                                                                      | `run`, `registerCommand` and codegen for scripts that drive the CLI                  |
| `better-supabase/testing`                                                                                                                  | `asUser`, `localAuth`, typed seeds and conformance kits                              |
| `better-supabase/events`, `/openapi`, `/otel`                                                                                              | CloudEvents, OpenAPI 3.1 and OpenTelemetry                                           |

### Frontend and local data

| Import                                          | What it gives you                                                                              |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `better-supabase/client`                        | Browser repositories that follow the session                                                   |
| `better-supabase/client/native`                 | The same for React Native, without `@supabase/ssr`, and keychain storage                       |
| `better-supabase/react`                         | Provider, typed hooks and the server session                                                   |
| `better-supabase/react/native`                  | OAuth, auth deep links, a protected route hook and `AuthGate` for Expo                         |
| `better-supabase/query`                         | TanStack Query options with table-based invalidation                                           |
| `better-supabase/tanstack-db`                   | TanStack DB collections that load through a query and write through the repositories           |
| `better-supabase/vue`, `/solid`, `/svelte`      | Live queries, presence, actions and the session for Vue, Solid and Svelte 5                    |
| `better-supabase/powersync`, `/powersync/react` | The repositories over PowerSync's local SQLite, `useWatch`, `useSyncStatus` and `useConflicts` |
| `better-supabase/expo-sqlite`                   | The same repositories over a local expo-sqlite database, with live queries                     |

### Server adapters

| Import                                                | What it gives you                                                                           |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `better-supabase/ssr`                                 | The `@supabase/ssr` cookie format for any framework                                         |
| `better-supabase/next`, `/next/image`, `/next/client` | Proxy, Server Components, route handlers, Storage images, session-change hook               |
| `better-supabase/hono`, `/orpc`                       | Hono middleware and REST resources, and an oRPC middleware                                  |
| `better-supabase/edge`                                | Fetch handlers for Supabase Edge Functions, Deno, Bun and Workers                           |
| `better-supabase/expo`                                | Expo Router server loaders, API routes and middleware                                       |
| `better-supabase/tanstack-start`, `/sveltekit`        | TanStack Start request middleware and a SvelteKit `handle` hook                             |
| `better-supabase/react-router`, `/h3`, `/elysia`      | Middleware for React Router, H3 2 and Elysia                                                |
| `better-supabase/h3/v1`, `/nuxt`                      | Middleware for Nitro 2, and a Nuxt module that registers it                                 |
| `better-supabase/node`, `/nestjs`                     | Node `http`, Express, Fastify, Koa and NestJS                                               |
| `better-supabase/astro`, `/solid-start`               | Astro middleware, Actions and images; SolidStart middleware and actions                     |
| `better-supabase/mcp`, `/mcp/sdk`                     | MCP servers whose tools run as the signed-in user, and bearer auth for the official MCP SDK |

### AI and agents

| Import                                                      | What it gives you                                                                                                 |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `better-supabase/ai-sdk`                                    | AI SDK message converters, gateway usage attribution and the model catalog                                        |
| `better-supabase/ai-sdk/chat`, `/ai-sdk/react`              | `createAssistant` for a chat route and `useAssistant` on the client                                               |
| `better-supabase/ai-sdk/files`, `/ai-sdk/cache`             | File parts from Storage and generated files, and a middleware that answers from the AI cache                      |
| `better-supabase/ai-sdk/batches`                            | AI SDK batches per tenant, polled from a job, with results in Postgres                                            |
| `better-supabase/ai-sdk/embeddings`, `/ai-sdk/memory`       | Embedders, reranking and a knowledge search tool; memory and recall tools and fact extraction                     |
| `better-supabase/ai-sdk/agents`, `/ai-sdk/mcp`              | A `ToolLoopAgent` from a stored agent with moderation, and MCP connections authorized through OAuth               |
| `better-supabase/ai-sdk/workflow`, `/ai-sdk/workflow/react` | Durable chat on the Workflow SDK with `durableChat`, `durableTurn` and `useDurableAssistant`                      |
| `better-supabase/chat-sdk`, `/chat-sdk/react`               | Chat SDK state in Postgres, the inbox adapter and channel webhooks                                                |
| `better-supabase/eve`                                       | eve on Supabase: route auth, connections over credential providers, memory, sessions and the inbox channel (Node) |

### Workflows, streams and credentials

| Import                                                | What it gives you                                                                   |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `better-supabase/workflow-sdk`, `/workflow-sdk/world` | Workflow SDK helpers bound to the caller, and a World on Supabase (Node)            |
| `better-supabase/workflow-sdk/builder`                | Compiles workflow builder graphs to Workflow SDK workflows and starts them          |
| `better-supabase/streams`, `/streams/redis`           | Resumable output for chats, workflows and agents, in Postgres or Redis              |
| `better-supabase/credentials`, `/vercel-connect`      | Third-party tokens behind a `credential_ref`, over Supabase Vault or Vercel Connect |

The 40 `better-supabase/blocks/*` subpaths are listed under [Blocks](#blocks).

## For AI agents

The package ships [Agent Skills](https://agentskills.io) for queries, APIs, auth and tests:

```bash
npx skills add ScaleDockHQ/better-supabase
# or, from the installed version:
pnpm better-supabase skills install
```

The docs are also available as [`/llms.txt`](https://bettersupabase.com/llms.txt), as Markdown at `/docs/<page>.md`, and through the read-only docs MCP server at `https://bettersupabase.com/mcp`.

## Documentation

The full documentation is at [bettersupabase.com/docs](https://bettersupabase.com/docs), and a runnable app for every adapter is in [`apps/examples`](./apps/examples).

## Contributing

Setup, the local stack, scripts and the release process are in [`CONTRIBUTING.md`](./CONTRIBUTING.md). The invariants and the "when you change X, also update Y" table for anyone changing the code, human or agent, are in [`AGENTS.md`](./AGENTS.md). Every user-visible change needs a changeset.

## Security

Report vulnerabilities privately; see [`SECURITY.md`](./SECURITY.md).

## License

[MIT](./LICENSE) © 2026 ScaleDock
