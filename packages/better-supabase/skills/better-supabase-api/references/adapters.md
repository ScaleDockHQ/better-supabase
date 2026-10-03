# Adapter setup

Each adapter wraps the same `betterSupabase` from `src/lib/supabase/index.ts`:

```ts title="src/lib/supabase/index.ts"
import { defineSupabase } from "better-supabase";

import { schema } from "./generated";

export type { Functions, Models } from "./generated";

export const betterSupabase = defineSupabase(schema);
```

## Next.js

```ts title="src/lib/supabase/server.ts"
import "server-only";
import { createNext } from "better-supabase/next";

import { betterSupabase } from "./index";

export const bs = createNext(betterSupabase);
```

```ts title="src/proxy.ts"
import type { NextRequest } from "next/server";

import { bs } from "./lib/supabase/server";

export const proxy = (request: NextRequest) => bs.proxy(request);
```

The proxy is the only place that refreshes sessions. Server Components,
route handlers and actions read the verified token:

```ts
const { db } = await bs.context();
export const GET = bs.route(
  (request, { db }) => db.customers.findMany({ limit: 20 }),
  { scopes: ["customers:read"] }, // only limits OAuth clients and agents
);
```

## Hono

```ts title="src/server.ts"
import { type HonoEnv, createHono } from "better-supabase/hono";
import { Hono } from "hono";

import { type Functions, type Models, betterSupabase } from "./lib/supabase";

const bs = createHono(betterSupabase);

const app = new Hono<HonoEnv<Models, Functions, unknown>>()
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

import { betterSupabase } from "./lib/supabase";

export const bs = createOrpc(betterSupabase);
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

import { betterSupabase } from "../_shared/supabase.ts";

const bs = createEdge(betterSupabase, { cors: true });

Deno.serve(
  bs.resources({ customers: { select: ["id", "name"] } }, { basePath: "/api" }),
);
```

## MCP

```ts title="supabase/functions/mcp/index.ts"
import { createMcp } from "better-supabase/mcp";
import { toSession } from "better-supabase/server";

import { betterSupabase } from "../_shared/supabase.ts";

const bs = createMcp(betterSupabase, {
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

Deno.serve(bs.fetch);
```

Tools run as the calling user, so RLS applies to every tool call. `scopes`
on `createMcp` only advertises scopes; `authorize` refuses the call. A
`delegation` that is unset means the user's own token, which no scope limits.
