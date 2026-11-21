import { describe, expect, it } from "vitest";

import type { CredentialProvider } from "../../src/credentials/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";
import {
  DEFAULT_SUPABASE_ACCESS_SERVICES,
  supabaseAccess,
  supabaseAccessFrom,
} from "../../src/vercel-sandbox/index.ts";

const PROJECT_URL = "https://abc.supabase.co";

function jwt(claims: Record<string, unknown>): string {
  const encode = (value: unknown): string =>
    btoa(JSON.stringify(value))
      .replaceAll("+", "-")
      .replaceAll("/", "_")
      .replaceAll("=", "");

  return `${encode({ alg: "ES256" })}.${encode(claims)}.signature`;
}

function rulesOf(options: ReturnType<typeof supabaseAccess>): unknown {
  const policy = options.networkPolicy;

  if (typeof policy !== "object") {
    throw new TypeError("expected an object policy");
  }

  const allow = policy.allow;

  if (allow === undefined || Array.isArray(allow)) {
    throw new TypeError("expected a record policy");
  }

  return Object.entries(allow).find(
    ([host]) => host === "abc.supabase.co",
  )?.[1];
}

describe("supabaseAccess", () => {
  it("allows only the project host and adds the headers at the firewall", () => {
    const options = supabaseAccess(
      { token: "user-token" },
      { url: PROJECT_URL, apikey: "sb_publishable_x" },
    );

    const headers = {
      authorization: "Bearer user-token",
      host: "abc.supabase.co",
      apikey: "sb_publishable_x",
    };

    expect(options.networkPolicy).toEqual({
      allow: {
        "abc.supabase.co": [
          ...DEFAULT_SUPABASE_ACCESS_SERVICES.map((service) => ({
            match: { path: { startsWith: `/${service}/v1` } },
            transform: [{ headers }],
          })),
          {
            response: {
              statusCode: 403,
              contentType: "application/json",
              body: expect.any(String),
            },
          },
        ],
      },
    });
    expect(options.timeout).toBeUndefined();
  });

  it("leaves the other paths alone when denyOtherPaths is false", () => {
    const rules = rulesOf(
      supabaseAccess(
        { token: "user-token" },
        { url: PROJECT_URL, denyOtherPaths: false },
      ),
    );

    expect(rules).toHaveLength(DEFAULT_SUPABASE_ACCESS_SERVICES.length);
    expect(JSON.stringify(rules)).not.toContain("response");
  });

  it("takes the services the caller lists, once each", () => {
    const options = supabaseAccess(
      { token: "t" },
      { url: PROJECT_URL, services: ["rest", "rest", "realtime"] },
    );

    const rules = rulesOf(options);

    expect(rules).toHaveLength(3);
    expect(JSON.stringify(rules)).toContain("/realtime/v1");
    expect(JSON.stringify(rules)).not.toContain("storage");
    expect(JSON.stringify(rules)).not.toContain("apikey");
  });

  it("ends the session before the token expires", () => {
    const now = 1_000_000;

    const fromClaim = supabaseAccess(
      { token: jwt({ role: "authenticated", exp: (now + 600_000) / 1000 }) },
      { url: PROJECT_URL, now: () => now },
    );

    expect(fromClaim.timeout).toBe(540_000);

    const explicit = supabaseAccess(
      {
        token: "opaque",
        expiresAt: Temporal.Instant.fromEpochMilliseconds(now + 30_000),
      },
      { url: PROJECT_URL, now: () => now, margin: 10_000 },
    );

    expect(explicit.timeout).toBe(20_000);

    const expired = supabaseAccess(
      {
        token: "opaque",
        expiresAt: Temporal.Instant.fromEpochMilliseconds(now),
      },
      { url: PROJECT_URL, now: () => now },
    );

    expect(expired.timeout).toBe(1000);
  });

  it("refuses a service role token and a secret key", () => {
    expect(() =>
      supabaseAccess(
        { token: jwt({ role: "service_role" }) },
        { url: PROJECT_URL },
      ),
    ).toThrow(/bypass row level security/);
    expect(() =>
      supabaseAccess(
        { token: "t" },
        { url: PROJECT_URL, apikey: "sb_secret_abc" },
      ),
    ).toThrow(/apikey/);
    expect(() =>
      supabaseAccess(
        { token: "t" },
        { url: PROJECT_URL, apikey: jwt({ role: "service_role" }) },
      ),
    ).toThrow(/apikey/);
  });

  it("refuses a project URL a sandbox cannot reach", () => {
    expect(() =>
      supabaseAccess({ token: "t" }, { url: "http://127.0.0.1:54321" }),
    ).toThrow(/https/);
    expect(() => supabaseAccess({ token: "t" }, { url: "nope" })).toThrow(
      /project URL/,
    );
  });
});

describe("supabaseAccessFrom", () => {
  const provider = (
    result: ReturnType<CredentialProvider["getToken"]>,
  ): Pick<CredentialProvider, "getToken"> => ({ getToken: () => result });

  const ref = { provider: "kms" };
  const subject = { type: "user", id: "u1" } as const;

  it("builds the options from the issued token", async () => {
    const result = await supabaseAccessFrom(
      provider(
        AsyncResult.ok({
          token: "issued",
          headers: {},
          expiresAt: Temporal.Instant.fromEpochMilliseconds(120_000),
        }),
      ),
      ref,
      { url: PROJECT_URL, subject, now: () => 0 },
    );

    expect(result.ok).toBe(true);
    expect(result.ok && result.data.timeout).toBe(60_000);
    expect(JSON.stringify(result.ok && result.data.networkPolicy)).toContain(
      "Bearer issued",
    );
  });

  it("passes a provider error through", async () => {
    const error = dbError("forbidden", "no", { hint: "X" });

    const result = await supabaseAccessFrom(
      provider(AsyncResult.err(error)),
      ref,
      { url: PROJECT_URL, subject },
    );

    expect(!result.ok && result.error).toMatchObject({
      kind: "forbidden",
      hint: "X",
    });
  });

  it("returns invalid_input for a service role token", async () => {
    const result = await supabaseAccessFrom(
      provider(
        AsyncResult.ok({ token: jwt({ role: "service_role" }), headers: {} }),
      ),
      ref,
      { url: PROJECT_URL, subject },
    );

    expect(!result.ok && result.error.kind).toBe("invalid_input");
  });
});
