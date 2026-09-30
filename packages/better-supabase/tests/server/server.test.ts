import { afterEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";

import { defineSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("createServer headers", () => {
  it("stamps per-request headers on the caller’s PostgREST requests", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(() =>
      Promise.resolve(Response.json([])),
    );
    vi.stubGlobal("fetch", fetch);
    const server = createServer(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks as never },
      headers: (request) => ({
        "x-channel": "api",
        "x-request-id": request.headers.get("x-request-id") ?? "",
      }),
    });
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    });

    for (const headers of [
      { "x-request-id": "r1" },
      { "x-request-id": "r2", authorization: `Bearer ${token}` },
    ]) {
      const ctx = await server.context(
        new Request("https://api.test/", { headers }),
      );
      await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
    }

    const sent = fetch.mock.calls.map(([, init]) => new Headers(init?.headers));
    expect(
      sent.map((headers) => [
        headers.get("x-channel"),
        headers.get("x-request-id"),
      ]),
    ).toEqual([
      ["api", "r1"],
      ["api", "r2"],
    ]);
    expect(sent[1]!.get("authorization")).toBe(`Bearer ${token}`);
  });
});

describe("createServer claims", () => {
  it("validates claims with the schema from sb.claims()", async () => {
    const sb = defineSupabase(schema).claims(
      z.object({ tenant_id: z.string().min(1) }),
    );
    const server = createServer(sb, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const request = async (claims: Record<string, unknown>) =>
      new Request("https://api.test/", {
        headers: {
          authorization: `Bearer ${await signer.sign({
            sub: "11111111-1111-4111-8111-111111111111",
            ...claims,
          })}`,
        },
      });

    const ok = await server.context(await request({ tenant_id: "t1" }));
    expect(ok.auth.kind === "user" && ok.auth.claims.tenant_id).toBe("t1");

    const bad = await server.context(await request({}));
    expect(bad.auth).toMatchObject({ kind: "invalid", reason: "claims" });
  });

  it("keeps PermDock claims a loose schema does not list", async () => {
    const sb = defineSupabase(schema).claims(
      z.looseObject({
        tenant_id: z.uuid().optional(),
        memberships: z
          .array(
            z.looseObject({
              scope: z.string(),
              id: z.string(),
              roles: z.array(z.string()),
            }),
          )
          .default([]),
      }),
    );
    const server = createServer(sb, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const org = "22222222-2222-4222-8222-222222222222";
    const permdock = {
      tenant_id: org,
      user_role: "member",
      roles: ["support"],
      memberships: [
        {
          scope: "project",
          id: "p1",
          within: { organization: org },
          roles: ["editor"],
          expiresAt: 1_900_000_000,
        },
      ],
      attrs: { department: "sales" },
      authz_ver: 7,
      memberships_truncated: true,
    };
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
      ...permdock,
    });
    const ctx = await server.context(
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    expect(ctx.auth.kind).toBe("user");
    if (ctx.auth.kind !== "user") return;
    expect(ctx.auth.claims).toMatchObject(permdock);
  });
});

describe("createServer userMetadata", () => {
  it("parses the profile with sb.userMetadata() and warns through the sb logger", async () => {
    const logger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };
    const sb = defineSupabase(schema, { logger }).userMetadata(
      z.object({ display_name: z.string() }),
    );
    const server = createServer(sb, {
      env,
      auth: { jwks: signer.jwks as never },
    });
    const request = async (metadata: Record<string, unknown>) =>
      new Request("https://api.test/", {
        headers: {
          authorization: `Bearer ${await signer.sign({
            sub: "11111111-1111-4111-8111-111111111111",
            user_metadata: metadata,
          })}`,
        },
      });

    const ok = await server.context(await request({ display_name: "Ada" }));
    expect(ok.auth).toMatchObject({
      kind: "user",
      profile: { display_name: "Ada" },
    });

    const bad = await server.context(await request({ display_name: 1 }));
    expect(bad.auth.kind).toBe("user");
    expect(bad.auth).not.toHaveProperty("profile");
    expect(logger.warn).toHaveBeenCalledOnce();
  });
});
