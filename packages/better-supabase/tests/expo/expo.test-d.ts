import type { ImmutableRequest, LoaderFunction } from "expo-server";

import { createServerLoader } from "expo-server";
import { describe, expectTypeOf, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createExpo } from "../../src/expo/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const bsb = createExpo(defineSupabase(schema), {
  env: {
    url: "https://abcdefghijklmnopqrst.supabase.co",
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(
      "https://abcdefghijklmnopqrst.supabase.co/auth/v1/.well-known/jwks.json",
    ),
  },
});

describe("bsb.loader", () => {
  it("is an expo-server LoaderFunction", () => {
    const loader = bsb.loader(({ db }) =>
      db.customers.list({ select: ["id", "name"] }).orThrow(),
    );

    expectTypeOf(loader).toExtend<
      LoaderFunction<readonly { id: string; name: string }[]>
    >();
  });

  it("composes inside createServerLoader through bsb.request", () => {
    const loader = createServerLoader(async (request: ImmutableRequest) => {
      const { db } = await bsb.request(request, { allow: ["user"] });

      return db.customers.list({ select: ["id"] }).orThrow();
    });

    expectTypeOf(loader).toExtend<LoaderFunction<readonly { id: string }[]>>();
  });
});
