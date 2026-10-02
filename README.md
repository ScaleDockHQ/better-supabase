# better-supabase

**A typed data layer, auth glue and CLI for Supabase apps, APIs, MCP servers and jobs.**

[![npm](https://img.shields.io/npm/v/better-supabase)](https://www.npmjs.com/package/better-supabase)
[![CI](https://img.shields.io/github/actions/workflow/status/ScaleDockHQ/better-supabase/ci.yml?label=CI)](https://github.com/ScaleDockHQ/better-supabase/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](./CODE_OF_CONDUCT.md)
![TypeScript](https://img.shields.io/badge/TypeScript-6%20%7C%207-3178c6.svg)

[Docs](https://bettersupabase.com/docs) · [Website](https://bettersupabase.com) · [Product](./PRODUCT.md) · [Design](./DESIGN.md) · [Agent guide](./AGENTS.md)

better-supabase removes the glue code every Supabase app rewrites: auth wiring, typed repositories, pagination, includes, nested filters, soft delete, timestamps, upserts, cache invalidation, list pages, storage paths and realtime topics. It builds directly on [`@supabase/server`](https://github.com/supabase/server), [`@supabase/middleware`](https://github.com/supabase/middleware) and [`@supabase/ssr`](https://github.com/supabase/ssr).

## Why better-supabase

- **Stronger generated types.** `better-supabase gen` wraps `supabase gen types` and adds relationship cardinality, unique keys, CHECK-constraint unions, typed jsonb and column maps for camelCase apps.
- **One request per query.** `db.customers.findMany({ where, include, orderBy })` compiles to a single PostgREST request, or to SQL on the direct-Postgres path.
- **Errors are values.** Every call returns a `Result` with a serializable `DbError`. Adapters turn it into RFC 9457 Problem Details with the right status.
- **RLS by construction.** Repositories are bound to the caller for each request. The service role is an explicit `admin()` call.
- **No auth calls on the hot path.** Valid access tokens are verified locally against the JWKS. Refresh happens once, in the proxy.
- **Adapters for where you run.** Next.js (including Cache Components), Hono, oRPC, Supabase Edge Functions and MCP servers.
- **Kits for the SQL every app repeats.** Jobs on Supabase Queues, webhook inboxes, idempotency keys, typed Storage and Realtime, vector search and Stripe entitlements, written into your declarative schema.
- **Checks you can run in CI.** `gen --check` for drift, `doctor` for security and performance findings (with SARIF), and `asUser` for RLS tests against the local stack.

## Install

```bash
pnpm add better-supabase @supabase/supabase-js
pnpm add -D @better-supabase/cli pg
```

Or start with `npx @better-supabase/cli init`, which detects your frameworks
and prints the install command. ESM only. Node 24 or later for the CLI; the runtime entries run on every WinterTC runtime. TypeScript 6 and 7 are tested.

## Quick start

### 1. Generate

```bash
supabase start
pnpm better-supabase init   # config, src/lib/supabase.ts and framework glue
pnpm better-supabase env    # URL and keys into .env.local
pnpm better-supabase gen    # database.types.ts and generated.ts
```

### 2. Query

```ts
import { createClient } from "@supabase/supabase-js";
import { defineSupabase } from "better-supabase";

import { schema } from "./lib/supabase/generated.ts";

export const sb = defineSupabase(schema);

const db = sb.connect(createClient(url, publishableKey));

const customers = await db.customers
  .findMany({
    select: ["id", "name"],
    where: { status: "active", notes: { some: { kind: "call" } } },
    include: { organization: { select: ["name"] } },
    orderBy: { name: "asc" },
    limit: 20,
  })
  .orThrow();
// { id: string; name: string; organization: { name: string } }[]
```

### Next.js

```tsx
// src/lib/supabase.server.ts
export const next = createNext(sb);

// src/proxy.ts
export const proxy = (request: NextRequest) => next.proxy(request);

// app/customers/page.tsx
export default async function Customers() {
  const { db } = await next.server();
  const customers = await db.customers
    .findMany({ select: ["id", "name"] })
    .orThrow();
  return <CustomerList customers={customers} />;
}
```

### Hono

```ts
const bs = createHono(sb);

const app = new Hono<BetterEnv<Models, Functions, unknown>>()
  .onError(bs.onError)
  .use("/api/*", bs.middleware())
  .get(
    "/api/customers",
    bs.handle((c, { db }) => db.customers.findMany({ limit: 20 })),
  );
```

### MCP

```ts
const mcp = createMcp(sb, {
  name: "crm",
  version: "1.0.0",
  resources: { customers: { select: ["id", "name", "status"] } },
});

Deno.serve(mcp.fetch);
```

## Works with

| Area       | Supported                                                                 |
| ---------- | ------------------------------------------------------------------------- |
| Frameworks | Next.js 16, Hono, oRPC, Supabase Edge Functions, Deno, Bun, Workers       |
| Frontend   | React 19, TanStack Query 5, live queries over Realtime                    |
| Validation | Zod, Valibot and any Standard Schema                                      |
| Standards  | OpenAPI 3.1, RFC 9457, OpenTelemetry, CloudEvents, Standard Webhooks, MCP |
| Testing    | Vitest, pgTAP, the Supabase local stack                                   |

## For AI agents

The package ships [Agent Skills](https://agentskills.io) for queries, APIs and tests:

```bash
npx skills add ScaleDockHQ/better-supabase
```

Maintainer rules for agents working on this repository are in [`AGENTS.md`](./AGENTS.md). The docs publish [`/llms.txt`](https://bettersupabase.com/llms.txt), every page as Markdown at `/docs/<page>.md`, and a read-only docs MCP server at `https://bettersupabase.com/mcp`.

## Documentation

[bettersupabase.com/docs](https://bettersupabase.com/docs). The source is in [`apps/docs/content/docs`](./apps/docs/content/docs), and runnable apps for every adapter are in [`apps/examples`](./apps/examples).

## Develop this repository

### Prerequisites

- Node 24 (`.nvmrc`) and pnpm 12. `devEngines` in `package.json` downloads the right Node for pnpm.
- Docker, for the local Supabase stack.
- The Vercel CLI, to pull environment variables (maintainers only; everything runs without them).

### First local run

```bash
pnpm install
vercel link           # maintainers: link the scaledock team's project
pnpm env:pull         # maintainers: hosted keys in .env.local
pnpm supabase:start   # API on 55421, Postgres on 55422
pnpm env:local        # local stack and Portless URLs in .env.development.local
pnpm dev:portless     # docs, marketing and the Next.js example over HTTPS
```

The first `pnpm dev:portless` asks to trust the Portless certificate authority.

### Local URLs and logins

| App             | URL                           |
| --------------- | ----------------------------- |
| Marketing       | `https://www.localhost`       |
| Docs            | `https://docs.localhost/docs` |
| Next.js example | `https://example.localhost`   |

The seed creates two users in the Acme organization, both with the password
`password123`: `admin@acme.test` (role `admin`) and `member@acme.test` (role `member`).

### Scripts

| Script                  | What it does                                                                                          |
| ----------------------- | ----------------------------------------------------------------------------------------------------- |
| `pnpm verify`           | The gate before every push: format, lint, prose, typecheck, Knip, boundaries, tests, doctor and audit |
| `pnpm dev:portless`     | Docs, marketing and the Next.js example on `.localhost` URLs                                          |
| `pnpm build`            | Builds every package and app                                                                          |
| `pnpm test`             | Unit and type tests                                                                                   |
| `pnpm test:integration` | Integration tests against the local stack                                                             |
| `pnpm test:e2e`         | The example apps against the local stack                                                              |
| `pnpm typecheck:matrix` | The published types against TypeScript 6 and 7                                                        |
| `pnpm size`             | Bundle size baselines and the WinterTC import check                                                   |
| `pnpm supabase:reset`   | Rebuilds the local database from the migrations and the seed                                          |
| `pnpm supabase:test`    | pgTAP tests in `supabase/tests`                                                                       |
| `pnpm db:gen`           | Regenerates the typed client in every example                                                         |
| `pnpm changeset`        | Records a user-visible change for the next release                                                    |

### Layout

```text
packages/better-supabase   the published library and its consumer skills
packages/cli               @better-supabase/cli: the better-supabase command, codegen and doctor
packages/next-config       shared Next.js config for docs and marketing
packages/ox-config         Oxlint presets, Oxfmt config and the anti-slop plugin
packages/typescript-config tsconfig presets
apps/docs                  bettersupabase.com/docs (Fumadocs)
apps/marketing             bettersupabase.com
apps/examples/*            one runnable app per adapter
tests/*                    bundle size, the TypeScript matrix, e2e and validation ports
supabase/                  the local stack: schemas, migrations, seed and pgTAP tests
docs/                      agent notes and architecture decision records
```

### Architecture

The package is one ESM module with subpath exports. The runtime entries import
no Node built-ins, so they run on every WinterTC runtime; the CLI, `postgres`
and `testing` entries run on Node. The CLI introspects the local database and
writes `database.types.ts` and `generated.ts` into each app, and those files
carry every type through inferring functions, without `declare module`. The
examples and the integration suite run against the fixture schema in
`supabase/`. [`AGENTS.md`](./AGENTS.md) lists the invariants.

### Deploy

Docs and marketing deploy to Vercel as two services of one project
(`vercel.json`), on the domain bettersupabase.com: `/docs` goes to the docs app
and everything else to marketing, in the `fra1` region. Only `main` deploys
(`git.deploymentEnabled`), and `turbo-ignore` skips a service whose app did not
change. The npm package is
released by `.github/workflows/release.yml`: changesets open a version pull
request, and merging it publishes to npm with provenance when the `NPM_PUBLISH`
variable is set.

## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md). Every user-visible change needs a changeset.

## Security

Report vulnerabilities privately; see [`SECURITY.md`](./SECURITY.md).

## License

[MIT](./LICENSE) © 2026 ScaleDock
