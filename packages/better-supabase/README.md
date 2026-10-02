# better-supabase

**A typed data layer, auth glue and CLI for Supabase apps, APIs, MCP servers and jobs.**

[![npm](https://img.shields.io/npm/v/better-supabase)](https://www.npmjs.com/package/better-supabase)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/ScaleDockHQ/better-supabase/blob/main/LICENSE)
![TypeScript](https://img.shields.io/badge/TypeScript-5.9%20%7C%206%20%7C%207-3178c6.svg)

`better-supabase gen` extends `supabase gen types` with relation cardinality, unique keys, CHECK unions and typed jsonb. The generated `schema` gives every table a typed repository that compiles to one PostgREST request, returns a `Result` instead of throwing, and runs as the caller so RLS always applies.

## Install

```bash
pnpm add better-supabase @supabase/supabase-js
pnpm add -D @better-supabase/cli pg
```

ESM only. The CLI ships as [`@better-supabase/cli`](https://www.npmjs.com/package/@better-supabase/cli), always at the same version as `better-supabase`, and needs Node 24 or later; the runtime entries run on every WinterTC runtime (Node, Deno, Bun, Workers, Supabase Edge Functions). TypeScript 5.9, 6 and 7 are tested.

## Quick start

Or start with `npx @better-supabase/cli init`, which detects your frameworks and prints the install command.

```bash
supabase start
pnpm better-supabase init   # config, src/lib/supabase.ts and framework glue
pnpm better-supabase gen    # database.types.ts and generated.ts
```

```ts
import { createClient } from '@supabase/supabase-js';
import { defineSupabase } from 'better-supabase';

import { schema } from './lib/supabase/generated.ts';

export const sb = defineSupabase(schema);

const db = sb.connect(createClient(url, publishableKey));

const result = await db.customers.findMany({
  select: ['id', 'name'],
  where: { status: 'active', notes: { some: { kind: 'call' } } },
  include: { organization: { select: ['name'] } },
  orderBy: { name: 'asc' },
  limit: 20,
});
if (!result.ok) return result; // DbError: kind, message, status, code
```

## Subpaths

| Import | What it gives you |
| --- | --- |
| `better-supabase` | `defineSupabase`, repositories, `Result`, `DbError`, `SPEC_PINS` |
| `better-supabase/config` | `defineConfig` and generators for `better-supabase.config.ts` |
| `better-supabase/client` | Browser repositories that follow the session |
| `better-supabase/react` | Provider, typed hooks and the server session |
| `better-supabase/query` | TanStack Query options with table-based invalidation |
| `better-supabase/server` | Repositories bound to the caller, admin and acting-as identities |
| `better-supabase/postgres` | The same repositories over direct Postgres |
| `better-supabase/ssr` | The `@supabase/ssr` cookie format for any framework |
| `better-supabase/next`, `/next/image` | Proxy, Server Components, route handlers, server actions, Storage images |
| `better-supabase/hono`, `/orpc`, `/edge` | Framework adapters |
| `better-supabase/mcp` | MCP servers whose tools run as the signed-in user |
| `better-supabase/jobs` | Supabase Queues jobs, idempotency keys and a webhook inbox |
| `better-supabase/list` | Search, facets, sorting and pagination from one definition |
| `better-supabase/storage`, `/realtime` | Typed bucket paths and broadcast topics |
| `better-supabase/env` | Validated Supabase settings |
| `better-supabase/events`, `/webhooks`, `/openapi`, `/otel` | CloudEvents, Standard Webhooks, OpenAPI 3.1 and OpenTelemetry |
| `better-supabase/plugins/*` | Timestamps, soft delete, tenant, actor, validation and runtime rules |
| `better-supabase/sql` | The SQL kit modules and read-set compiler behind `better-supabase sql` |
| `better-supabase/lint` | Editor rules for unbounded reads and unscoped deletes |
| `better-supabase/testing` | `asUser`, `localAuth`, typed seeds and conformance kits |

## For AI agents

The package ships [Agent Skills](https://agentskills.io) in `skills/`:

```bash
npx skills add ScaleDockHQ/better-supabase
# or, from the installed version:
pnpm better-supabase skills install
```

The docs are also available as [`/llms.txt`](https://bettersupabase.com/llms.txt), as Markdown at `/docs/<page>.md`, and through the docs MCP server at `https://bettersupabase.com/mcp`.

## Documentation

[bettersupabase.com/docs](https://bettersupabase.com/docs)

## License

[MIT](https://github.com/ScaleDockHQ/better-supabase/blob/main/LICENSE)
