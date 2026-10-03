# Adapter setup

Each adapter wraps the same `sb` from `src/lib/supabase.ts`:

```ts title="src/lib/supabase.ts"
import { defineSupabase } from "better-supabase";

import { schema } from "./supabase/generated";

export type { Functions, Models } from "./supabase/generated";

export const sb = defineSupabase(schema);
```

## Next.js

```ts title="src/lib/supabase.server.ts"
import { createNext } from "better-supabase/next";

import { sb } from "./supabase";

export const next = createNext(sb);
```

```ts title="src/proxy.ts"
import type { NextRequest } from "next/server";

import { next } from "./lib/supabase.server";

export const proxy = (request: NextRequest) => next.proxy(request);
```

The proxy is the only place that refreshes sessions. Server Components,
route handlers and actions read the verified token:

```ts
const { db } = await next.server();
export const GET = next.route(
  (request, { db }) => db.customers.findMany({ limit: 20 }),
  { scopes: ["customers:read"] }, // only limits OAuth clients and agents
);
```

## Hono

```ts title="src/server.ts"
import { type BetterEnv, createHono } from "better-supabase/hono";
import { Hono } from "hono";

import { type Functions, type Models, sb } from "./lib/supabase";

const bs = createHono(sb);

const app = new Hono<BetterEnv<Models, Functions, unknown>>()
  .onError(bs.onError)
  .use("/api/*", bs.middleware())
  .get("/api/me", (c) => c.json({ kind: c.var.auth.kind }))
  .route(
    "/api/customers",
    bs.resource("customers", { select: ["id", "name"] }),
  );

export default app;
```

## oRPC

```ts title="src/router.ts"
import { os } from "@orpc/server";
import { createOrpc, type OrpcRequestContext } from "better-supabase/orpc";

import { sb } from "./lib/supabase";

export const bs = createOrpc(sb);
const authed = os.$context<OrpcRequestContext>().use(bs.middleware());

export const router = {
  customers: authed.handler(({ context }) =>
    bs.unwrap(context.db.customers.findMany({ limit: 20 })),
  ),
};
```

## Edge Functions

```ts title="supabase/functions/api/index.ts"
import { createEdge } from "better-supabase/edge";

import { sb } from "../_shared/supabase.ts";

const bs = createEdge(sb, { cors: true });

Deno.serve(
  bs.resources({ customers: { select: ["id", "name"] } }, { basePath: "/api" }),
);
```

## MCP

```ts title="supabase/functions/mcp/index.ts"
import { createMcp } from "better-supabase/mcp";
import { toSession } from "better-supabase/server";

import { sb } from "../_shared/supabase.ts";

const mcp = createMcp(sb, {
  name: "crm",
  version: "0.1.0",
  scopes: ["openid", "crm.read"],
  allowedOrigins: ["https://claude.ai"],
  allowedHosts: ["crm.example.com", "localhost"],
  resourceDocumentation: "https://crm.example.com/docs/mcp",
  resources: {
    customers: { select: ["id", "name"], pagination: "cursor" },
  },
  authorize: (ctx) => {
    const session = toSession(ctx.auth);
    const granted =
      session.kind === "user" ? session.delegation?.scopes : undefined;
    return !granted || granted.includes("crm.read")
      ? { allowed: true }
      : { allowed: false, reason: "Needs crm.read", scopes: ["crm.read"] };
  },
});

Deno.serve(mcp.fetch);
```

Tools run as the calling user, so RLS applies to every tool call. `scopes`
on `createMcp` only advertises scopes; `authorize` refuses the call. A
`delegation` that is unset means the user's own token, which no scope limits.
