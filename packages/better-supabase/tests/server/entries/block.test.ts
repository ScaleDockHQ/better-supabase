import type { PostgresApi } from "@supabase/server/middleware/postgres";

import { defineMiddleware, pipeline } from "@supabase/middleware";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../../src/core/define.ts";
import { withBetterSupabase } from "../../../src/server/composite.ts";
import { withBlock } from "../../../src/server/entries/block.ts";
import { createServer } from "../../../src/server/server.ts";
import { createTestSigner } from "../../../src/testing/jwt.ts";
import { fakeSql } from "../../fixtures/fake-sql.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();
const server = createServer(defineSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks as never },
  prefetchJwks: false,
});

describe("withBlock", () => {
  it("builds a block from the entries before it, after withBetterSupabase", async () => {
    const fake = fakeSql([[/select 1/, [{ one: 1 }]]]);
    const withPostgresAdmin = defineMiddleware<
      "postgresAdmin",
      undefined,
      Record<never, never>,
      PostgresApi
    >({
      key: "postgresAdmin",
      run: () => () =>
        // SAFETY: the block only calls queryRaw, which the fake implements.
        Promise.resolve({ postgresAdmin: fake.sql as unknown as PostgresApi }),
    });
    const built: unknown[] = [];
    const fetch = pipeline(
      [
        withBetterSupabase(server, { allow: ["anon"] }),
        withPostgresAdmin(),
        withBlock(
          "probe",
          (ctx: {
            readonly postgresAdmin: PostgresApi;
            readonly authMode: string;
          }) => {
            built.push(ctx.authMode);
            return { ping: () => ctx.postgresAdmin.queryRaw("select 1") };
          },
        ),
      ],
      async (_req, ctx) => Response.json(await ctx.probe.ping()),
    );
    const response = await fetch(new Request("https://api.test/jobs"));
    expect(await response.json()).toEqual([{ one: 1 }]);
    expect(built).toEqual(["none"]);
  });
});
