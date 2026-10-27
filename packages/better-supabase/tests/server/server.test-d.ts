import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expectTypeOf, it } from "vitest";

import type { Db } from "../../src/core/repository-types.ts";
import type { AsyncResult } from "../../src/core/result.ts";
import type {
  BetterServer,
  ServerContext,
} from "../../src/server/server-types.ts";
import type { BucketClient, StorageApi } from "../../src/storage/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const bsb = createServer(defineSupabase(schema));

type Server =
  typeof bsb extends BetterServer<infer M, infer F, infer E>
    ? { M: M; F: F; E: E }
    : never;

describe("createServer forContext", () => {
  it("resolves to the same Postgres repositories as actingAs", () => {
    expectTypeOf(bsb.forContext({})).toEqualTypeOf<
      AsyncResult<Db<Server["M"], Server["F"], Server["E"], undefined>>
    >();
    expectTypeOf(bsb.forContext({}).orThrow()).resolves.toEqualTypeOf<
      ReturnType<typeof bsb.actingAs>
    >();
  });

  it("takes claimsFor with sync or async claims", () => {
    createServer(defineSupabase(schema), {
      claimsFor: (userId, context) => {
        expectTypeOf(userId).toEqualTypeOf<string>();
        expectTypeOf(context.tenant).toEqualTypeOf<string | undefined>();

        return { organization_ids: [context.tenant] };
      },
    });
    createServer(defineSupabase(schema), {
      claimsFor: async () => ({ user_role: "admin" }),
    });
  });
});

describe("storage on the context", () => {
  it("types ctx.storage and db.$storage as a StorageApi", () => {
    type Ctx = ServerContext<Server["M"], Server["F"], Server["E"]>;

    expectTypeOf<Ctx["storage"]>().toEqualTypeOf<StorageApi | undefined>();
    expectTypeOf<Ctx["db"]["$storage"]>().toEqualTypeOf<StorageApi>();
    expectTypeOf<
      NonNullable<Ctx["sql"]>["$storage"]
    >().toEqualTypeOf<StorageApi>();
  });
});

describe("buckets on the server db", () => {
  it("carries $buckets into db, sql, admin and $with", () => {
    const logos = defineBucket({ id: "logos", path: "{userId}/logo.webp" });
    const server = createServer(defineSupabase(schema).buckets({ logos }));

    type Logos = BucketClient<"{userId}/logo.webp", "logos">;

    expectTypeOf(server.admin().$buckets.logos).toEqualTypeOf<Logos>();
    expectTypeOf(
      server.admin().$with({}).$buckets.logos,
    ).toEqualTypeOf<Logos>();
    expectTypeOf(
      server.dbFor({ kind: "none", reason: "none" }).$buckets.logos,
    ).toEqualTypeOf<Logos>();
  });
});

describe("auth admin on the server db", () => {
  it("types $authAdmin on admin() and nowhere else", () => {
    const server = createServer(defineSupabase(schema));

    expectTypeOf(server.admin().$authAdmin).toEqualTypeOf<
      SupabaseClient["auth"]["admin"]
    >();
    expectTypeOf(
      server.dbFor({ kind: "none", reason: "none" }),
    ).not.toHaveProperty("$authAdmin");
  });
});
