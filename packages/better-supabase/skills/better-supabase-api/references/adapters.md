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
import { createHono } from "better-supabase/hono";

import { betterSupabase } from "./lib/supabase";

const bs = createHono(betterSupabase);

// bs.app() is new Hono<typeof bs.Env>() with bs.onError installed.
const app = bs
  .app()
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

For a contract from `@orpc/contract`, use the same middleware on the
implementer and serve it with `OpenAPIHandler`, so errors keep their HTTP
status (RLS denials answer 403):

```ts title="src/server.ts"
const os = implement(contract)
  .$context<OrpcRequestContext>()
  .use(bs.middleware());
const router = os.router({
  customers: {
    get: os.customers.get.handler(({ context, input }) =>
      bs.unwrap(context.db.customers.findById(input.id)),
    ),
  },
});
const handle = bs.fetchHandler(new OpenAPIHandler(router), { prefix: "/api" });
const app = new Hono().all("/api/*", (c) => handle(c.req.raw));
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
  advertisedScopes: ["openid", "crm.read"],
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

Tools run as the calling user, so RLS applies to every tool call.
`advertisedScopes` only advertises scopes; `requiredScopes` refuses delegated
tokens that lack one, and `authorize` refuses a single call. The session comes
from the `Authorization` header only, never from a cookie. A
`delegation` that is unset means the user's own token, which no scope limits.

On Supabase Edge Functions, set `[functions.mcp] verify_jwt = false` in
`supabase/config.toml`; the gateway's own 401 has no OAuth challenge. The
server then derives its public URL from `SUPABASE_FUNCTION_SLUG` and the
gateway's `X-Forwarded-*` headers and serves the metadata at
`/functions/v1/mcp/oauth-protected-resource`, so leave `resource` unset there.
CORS preflights are answered by default (`cors: false` turns them off).
To keep a Supabase library MCP block's pipeline instead, add
`withBetterSupabase(betterSupabase)()` from `better-supabase/server` after its
`withSupabase` entry for `ctx.db`.

### MCP on the official SDK

```ts title="src/mcp.ts"
import { createMcpHandler, McpServer } from "@modelcontextprotocol/server";
import { createMcpAuth, withBetterSupabase } from "better-supabase/mcp/sdk";

import { betterSupabase } from "./lib/supabase/schema";

const auth = createMcpAuth(betterSupabase, {
  resource: "https://crm.example.com/mcp",
  advertisedScopes: ["crm.read"],
});

const handler = createMcpHandler(() => {
  const server = withBetterSupabase(
    new McpServer({ name: "crm", version: "0.1.0" }),
    auth,
  );
  server.registerTool("count_customers", {}, async ({ db }) => {
    const count = await db.customers.count().orThrow();
    return { content: [{ type: "text", text: String(count) }] };
  });
  return server;
});

export default { fetch: auth.serve(handler) };
```

`auth.serve` answers the RFC 9728 metadata and the 401 challenge, then passes
the verified `authInfo` to the SDK handler. `auth.verifier` plugs into the
SDK's own `requireBearerAuth` when you keep your own routing.
