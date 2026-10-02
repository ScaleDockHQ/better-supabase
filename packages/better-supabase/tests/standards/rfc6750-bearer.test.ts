import { Hono } from "hono";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { problemResponse } from "../../src/core/problem.ts";
import { type BetterEnv, createHono } from "../../src/hono/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import {
  type Functions,
  type Models,
  schema,
} from "../fixtures/generated-camel.ts";

// RFC 6750 section 3 and RFC 9110 section 11.6.1: `Bearer` followed by comma
// separated auth-params `token = quoted-string`.
const TOKEN = "[!#$%&'*+.^_`|~0-9A-Za-z-]+";
const QUOTED = '"(?:[^"\\\\]|\\\\.)*"';
const CHALLENGE = new RegExp(
  `^Bearer(?: ${TOKEN}=(?:${TOKEN}|${QUOTED})(?:, ${TOKEN}=(?:${TOKEN}|${QUOTED}))*)?$`,
);

function params(header: string): Record<string, string> {
  return Object.fromEntries(
    [...header.matchAll(/([a-z_]+)="([^"]*)"/g)].map((match) => [
      match[1]!,
      match[2]!,
    ]),
  );
}

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();

describe("RFC 6750 Bearer token challenges", () => {
  it("answers 401 with a Bearer challenge carrying realm and error=invalid_token (section 3.1)", () => {
    const header = problemResponse(dbError("unauthorized", "Expired"), {
      realm: "crm",
    }).headers.get("www-authenticate")!;
    expect(header).toMatch(CHALLENGE);
    expect(params(header)).toEqual({ realm: "crm", error: "invalid_token" });
  });

  it("omits the error code when the request had no credentials (section 3.1)", () => {
    const header = problemResponse(
      dbError("unauthorized", "Sign in", { code: "MISSING_CREDENTIALS" }),
    ).headers.get("www-authenticate")!;
    expect(header).toMatch(CHALLENGE);
    expect(params(header)).toEqual({ realm: "supabase" });
  });

  it("answers a missing scope with 403, error=insufficient_scope and the needed scope (section 3.1)", () => {
    const response = problemResponse(
      dbError("forbidden", "Needs scope", {
        code: "INSUFFICIENT_SCOPE",
        scopes: ["crm.read", "crm.write"],
      }),
    );
    expect(response.status).toBe(403);
    const header = response.headers.get("www-authenticate")!;
    expect(header).toMatch(CHALLENGE);
    expect(params(header)).toEqual({
      realm: "supabase",
      error: "insufficient_scope",
      scope: "crm.read crm.write",
    });
  });

  it("strips quotes from realm and scope so the quoted-string stays valid", () => {
    const header = problemResponse(
      dbError("forbidden", "x", {
        code: "INSUFFICIENT_SCOPE",
        scopes: ['a"b'],
      }),
      { realm: 'my"realm' },
    ).headers.get("www-authenticate")!;
    expect(header).toMatch(CHALLENGE);
    expect(header).toContain('realm="myrealm"');
    expect(header).toContain('scope="ab"');
  });

  it("keeps an existing WWW-Authenticate header", () => {
    const header = problemResponse(dbError("unauthorized", "x"), {
      headers: { "www-authenticate": 'Bearer realm="other"' },
    }).headers.get("www-authenticate");
    expect(header).toBe('Bearer realm="other"');
  });

  it("reads the token from the Authorization header with the Bearer scheme (section 2.1)", async () => {
    const sb = defineSupabase(schema);
    const bs = createHono(sb, {
      env: {
        url: PROJECT_URL,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      },
      auth: { jwks: signer.jwks as never },
    });
    const app = new Hono<BetterEnv<Models, Functions, unknown>>()
      .onError(bs.onError)
      .use("/api/*", bs.middleware())
      .get("/api/me", (c) => c.json({ ok: true }));
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    });
    expect(
      (
        await app.request("/api/me", {
          headers: { authorization: `Bearer ${token}` },
        })
      ).status,
    ).toBe(200);
    const rejected = await app.request("/api/me", {
      headers: { authorization: "Bearer not-a-jwt" },
    });
    expect(rejected.status).toBe(401);
    expect(rejected.headers.get("www-authenticate")).toMatch(CHALLENGE);
    expect(params(rejected.headers.get("www-authenticate")!)).toMatchObject({
      error: "invalid_token",
    });
  });
});
