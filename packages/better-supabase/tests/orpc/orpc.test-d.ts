import type { SupabaseClient } from "@supabase/supabase-js";

import { oc } from "@orpc/contract";
import { implement, os } from "@orpc/server";
import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { OrpcRequestContext } from "../../src/orpc/index.ts";
import type { BucketClient } from "../../src/storage/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createOrpc } from "../../src/orpc/index.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

declare const client: SupabaseClient;
const betterSupabase = defineSupabase(schema);
const bsb = createOrpc(betterSupabase);
const db = betterSupabase.connect(client);

describe("unwrap", () => {
  it("infers the data type of a Result or AsyncResult", () => {
    expectTypeOf(bsb.unwrap(ok({ id: "c1" }))).toEqualTypeOf<
      Promise<{ id: string }>
    >();
    expectTypeOf(
      bsb.unwrap(db.customers.get("c1", { select: ["id", "name"] })),
    ).toEqualTypeOf<Promise<{ id: string; name: string }>>();
    expectTypeOf(
      bsb.unwrap<{ id: string }>(err(dbError("conflict", "Taken"))),
    ).toEqualTypeOf<Promise<{ id: string }>>();
  });

  it("passes plain values through", () => {
    expectTypeOf(bsb.unwrap(Promise.resolve(1))).toEqualTypeOf<
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
        expectTypeOf(context.bsb.auth).toEqualTypeOf<AuthState<Claims>>();

        return null;
      });
  });

  it("guards one contract procedure that has a typed output", () => {
    const contract = {
      remove: oc
        .input(v.object({ id: v.string() }))
        .output(v.object({ deleted: v.boolean() })),
    };

    const impl = implement(contract)
      .$context<OrpcRequestContext>()
      .use(bsb.middleware());

    impl.remove
      .use(bsb.middleware({ permission: "customers.delete" }))
      .handler(({ context }) => {
        expectTypeOf(context.auth).toEqualTypeOf<AuthState>();

        return { deleted: true };
      });
  });

  it("keeps untyped claims for untyped definitions", () => {
    os.$context<OrpcRequestContext>()
      .use(bsb.middleware())
      .handler(({ context }) => {
        expectTypeOf(context.auth).toEqualTypeOf<AuthState>();

        return null;
      });
  });
});

describe("betterSupabase.buckets() in oRPC", () => {
  it("types db.$buckets on the server and the procedure context", () => {
    const logos = defineBucket({ id: "logos", path: "{userId}/logo.webp" });
    const withBuckets = createOrpc(defineSupabase(schema).buckets({ logos }));

    type Logos = BucketClient<"{userId}/logo.webp", "logos">;

    expectTypeOf(withBuckets.admin().$buckets.logos).toEqualTypeOf<Logos>();
    withBuckets.authed().handler(({ context }) => {
      expectTypeOf(context.db.$buckets.logos).toEqualTypeOf<Logos>();

      return null;
    });
  });
});
