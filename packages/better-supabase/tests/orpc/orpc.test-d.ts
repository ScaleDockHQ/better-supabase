import type { SupabaseClient } from "@supabase/supabase-js";

import { os } from "@orpc/server";
import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createOrpc, type OrpcRequestContext } from "../../src/orpc/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const betterSupabase = defineSupabase(schema);
const bs = createOrpc(betterSupabase);
const db = betterSupabase.connect(client);

describe("unwrap", () => {
  it("infers the data type of a Result or AsyncResult", () => {
    expectTypeOf(bs.unwrap(ok({ id: "c1" }))).toEqualTypeOf<
      Promise<{ id: string }>
    >();
    expectTypeOf(
      bs.unwrap(db.customers.findById("c1", { select: ["id", "name"] })),
    ).toEqualTypeOf<Promise<{ id: string; name: string }>>();
    expectTypeOf(
      bs.unwrap<{ id: string }>(err(dbError("conflict", "Taken"))),
    ).toEqualTypeOf<Promise<{ id: string }>>();
  });

  it("passes plain values through", () => {
    expectTypeOf(bs.unwrap(Promise.resolve(1))).toEqualTypeOf<
      Promise<number>
    >();
  });
});

const Claims = v.object({ tenant_id: v.string(), user_role: v.string() });
type Claims = v.InferOutput<typeof Claims>;

describe("betterSupabase.claims(schema) in oRPC", () => {
  it("types the claims the middleware adds to context", () => {
    const typed = createOrpc(betterSupabase.claims(Claims));
    os.$context<OrpcRequestContext>()
      .use(typed.middleware())
      .handler(({ context }) => {
        expectTypeOf(context.auth).toEqualTypeOf<AuthState<Claims>>();
        expectTypeOf(context.bs.auth).toEqualTypeOf<AuthState<Claims>>();
        return null;
      });
  });

  it("keeps untyped claims for untyped definitions", () => {
    os.$context<OrpcRequestContext>()
      .use(bs.middleware())
      .handler(({ context }) => {
        expectTypeOf(context.auth).toEqualTypeOf<AuthState>();
        return null;
      });
  });
});
