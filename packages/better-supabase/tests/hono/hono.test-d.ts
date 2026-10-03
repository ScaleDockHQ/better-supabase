import { Hono } from "hono";
import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { Functions, Models } from "../fixtures/generated-camel.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createHono, type HonoEnv } from "../../src/hono/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const Claims = v.object({ tenant_id: v.string(), user_role: v.string() });
type Claims = v.InferOutput<typeof Claims>;

describe("betterSupabase.claims(schema) in Hono", () => {
  const bs = createHono(defineSupabase(schema).claims(Claims));

  it("types the claims in c.var and the handler context", () => {
    new Hono<HonoEnv<Models, Functions, unknown, Claims>>()
      .use(bs.middleware())
      .get(
        "/",
        bs.handler((c, ctx) => {
          expectTypeOf(c.var.auth).toEqualTypeOf<AuthState<Claims>>();
          expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();
          if (ctx.auth.kind === "user") {
            expectTypeOf(ctx.auth.claims.user_role).toEqualTypeOf<string>();
          }
          return null;
        }),
      );
  });

  it("keeps untyped claims for untyped definitions", () => {
    const untyped = createHono(defineSupabase(schema));
    untyped.handler((_c, ctx) => {
      expectTypeOf(ctx.auth).toEqualTypeOf<AuthState>();
      return null;
    });
  });
});
