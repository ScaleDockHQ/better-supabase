import type { PostgresApi } from "@supabase/server/middleware/postgres";

import { seedContext } from "@supabase/middleware";
import { describe, expect, it } from "vitest";

import type { RequestContext } from "../../src/core/plugin.ts";

import { defineSupabase } from "../../src/core/define.ts";
import {
  contextFromSupabase,
  type SupabaseAuthContext,
  withBetterPostgres,
  withBetterSupabase,
} from "../../src/server/middleware.ts";
import { capturingClient } from "../fixtures/client.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);
const ANON = {
  actor: { id: "anon", kind: "anon", role: "anon" },
  claims: { role: "anon" },
};
const userClaims = {
  id: "11111111-1111-4111-8111-111111111111",
  role: "authenticated",
  email: "ada@example.test",
};
const jwtClaims = { sub: userClaims.id, role: "authenticated", aal: "aal1" };

function auth(fields: Partial<SupabaseAuthContext>): SupabaseAuthContext {
  return { jwtClaims: null, userClaims: null, authMode: "none", ...fields };
}

describe("contextFromSupabase", () => {
  it("maps a user to a user actor with the verified claims", () => {
    expect(
      contextFromSupabase(
        auth({
          authMode: "user",
          userClaims,
          jwtClaims,
        }),
      ),
    ).toEqual({
      actor: { kind: "user", ...userClaims },
      claims: jwtClaims,
    });
  });

  it("carries the impersonator like authContext does", () => {
    const claims = { sub: "u1", act: { sub: "admin-1", reason: "ticket" } };
    expect(
      contextFromSupabase(
        auth({
          authMode: "user",
          userClaims: { id: "u1" },
          jwtClaims: claims,
        }),
      ),
    ).toEqual({
      actor: { id: "u1", kind: "user", impersonator: "admin-1" },
      claims,
    });
  });

  it("omits a missing role and email, and defaults claims to empty", () => {
    expect(
      contextFromSupabase(auth({ authMode: "user", userClaims: { id: "u1" } })),
    ).toEqual({ actor: { id: "u1", kind: "user" }, claims: {} });
  });

  it("treats a user mode without user claims as anon", () => {
    expect(contextFromSupabase(auth({ authMode: "user" }))).toEqual(ANON);
  });

  it("maps the secret key to the service role", () => {
    expect(contextFromSupabase(auth({ authMode: "secret" }))).toEqual({
      actor: { id: "service", kind: "service", role: "service_role" },
      claims: { role: "service_role" },
    });
  });

  it("maps publishable and no auth to anon", () => {
    expect(contextFromSupabase(auth({ authMode: "publishable" }))).toEqual(
      ANON,
    );
    expect(contextFromSupabase(auth({ authMode: "none" }))).toEqual(ANON);
  });

  it("refuses an auth mode it does not know", () => {
    expect(() =>
      contextFromSupabase(auth({ authMode: "magic" as never })),
    ).toThrow('contextFromSupabase: unknown auth mode "magic"');
  });
});

describe("withBetterSupabase", () => {
  it("contributes ctx.db bound to ctx.supabase and the caller", async () => {
    const { client, requests } = capturingClient(() => ({
      body: [{ id: "c1" }],
    }));
    let seen: { context: RequestContext; client: unknown } | undefined;
    const handler = withBetterSupabase(betterSupabase)(async (_req, ctx) => {
      seen = { context: ctx.db.$context, client: ctx.db.$client };
      const rows = await ctx.db.customers
        .findMany({ select: ["id"] })
        .orThrow();
      return Response.json(rows);
    });
    const response = await handler(new Request("https://api.test/"), {
      ...seedContext(undefined),
      ...auth({
        authMode: "user",
        userClaims,
        jwtClaims,
      }),
      supabase: client,
    });
    expect(await response.json()).toEqual([{ id: "c1" }]);
    expect(seen?.client).toBe(client);
    expect(seen?.context.actor).toEqual({ kind: "user", ...userClaims });
    expect(requests.map((request) => request.path)).toEqual([
      "/rest/v1/customers",
    ]);
  });
});

describe("withBetterPostgres", () => {
  it("contributes ctx.sql over ctx.postgres", async () => {
    const fake = fakeSql([[/customers/, [{ row: { id: "c1" } }]]]);
    let context: RequestContext | undefined;
    const handler = withBetterPostgres(betterSupabase)(async (_req, ctx) => {
      context = ctx.sql.$context;
      const rows = await ctx.sql.customers
        .findMany({ select: ["id"] })
        .orThrow();
      return Response.json(rows);
    });
    const response = await handler(new Request("https://api.test/"), {
      ...seedContext(undefined),
      ...auth({ authMode: "secret" }),
      // SAFETY: the executor only calls queryRaw, which the fake implements.
      postgres: fake.sql as unknown as PostgresApi,
    });
    expect(await response.json()).toEqual([{ id: "c1" }]);
    expect(context?.actor?.kind).toBe("service");
    expect(fake.texts()).toHaveLength(1);
    expect(fake.texts()[0]).toContain("customers");
  });
});
