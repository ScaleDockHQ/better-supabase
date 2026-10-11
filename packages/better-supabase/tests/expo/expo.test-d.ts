import type { ImmutableRequest, LoaderFunction } from "expo-server";

import { createServerLoader } from "expo-server";
import { describe, expectTypeOf, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createExpo } from "../../src/expo/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const bs = createExpo(defineSupabase(schema), {
  env: {
    url: "https://abcdefghijklmnopqrst.supabase.co",
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(
      "https://abcdefghijklmnopqrst.supabase.co/auth/v1/.well-known/jwks.json",
    ),
  },
});

describe("bs.loader", () => {
  it("is an expo-server LoaderFunction", () => {
    const loader = bs.loader(({ db }) =>
      db.customers.findMany({ select: ["id", "name"] }).orThrow(),
    );
    expectTypeOf(loader).toExtend<
      LoaderFunction<readonly { id: string; name: string }[]>
    >();
  });

  it("composes inside createServerLoader through bs.request", () => {
    const loader = createServerLoader(async (request: ImmutableRequest) => {
      const { db } = await bs.request(request, { allow: ["user"] });
      return db.customers.findMany({ select: ["id"] }).orThrow();
    });
    expectTypeOf(loader).toExtend<LoaderFunction<readonly { id: string }[]>>();
  });
});
