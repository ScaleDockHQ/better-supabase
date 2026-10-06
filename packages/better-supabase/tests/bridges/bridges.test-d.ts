import type { Contributions } from "@supabase/middleware";

import { withSupabase } from "@supabase/server";
import { Hono } from "hono";
import { describe, expectTypeOf, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { toEdge } from "../../src/edge/index.ts";
import { toHono } from "../../src/hono/index.ts";
import { toReactRouter } from "../../src/react-router/index.ts";
import { withBetterSupabase } from "../../src/server/composite.ts";
import { createServer } from "../../src/server/server.ts";
import { toSvelteKit } from "../../src/sveltekit/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const server = createServer(defineSupabase(schema));
const entry = withBetterSupabase(server);
type Keys = Contributions<readonly [typeof entry]>;

describe("bridges", () => {
  it("types c.var on a chained Hono app", () => {
    new Hono().use(toHono([entry])).get("/", (c) => {
      expectTypeOf(c.var.db).toEqualTypeOf<Keys["db"]>();
      return c.text("ok");
    });
  });

  it("types the edge handler's ctx", () => {
    toEdge([entry], (_request, ctx) => {
      expectTypeOf(ctx.bs).toEqualTypeOf<Keys["bs"]>();
      return new Response(null);
    });
  });

  it("rejects entries that collide", () => {
    // @ts-expect-error -- withSupabase and withBetterSupabase both contribute `authMode`.
    toEdge([withSupabase(), entry], () => new Response(null));
    // @ts-expect-error -- the same collision through the SvelteKit bridge.
    toSvelteKit([withSupabase(), entry]);
  });

  it("types the React Router context value", () => {
    const middleware = toReactRouter([entry], "key" as const);
    expectTypeOf<Parameters<typeof middleware>[0]["context"]["set"]>()
      .parameter(1)
      .toEqualTypeOf<Keys>();
  });
});
