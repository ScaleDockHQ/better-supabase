import { describe, expect, it, vi } from "vitest";

import type { WarmDeps } from "../../src/server/warm.ts";

import { createSupabase } from "../../src/core/define.ts";
import { createServer } from "../../src/server/server.ts";
import { warmUp } from "../../src/server/warm.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const signer = await createTestSigner();

function deps(overrides: Partial<WarmDeps> = {}): WarmDeps {
  return {
    url: () => PROJECT_URL,
    readUrl: () => undefined,
    publishableKey: () => "sb_publishable_test",
    fetch: vi.fn<typeof fetch>(async () => new Response("{}")),
    jwks: () => undefined,
    ...overrides,
  };
}

describe("warmUp", () => {
  it("pings PostgREST and the read replica with the publishable key", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(
      async () => new Response("{}"),
    );

    const report = await warmUp(
      deps({ fetch, readUrl: () => "https://read.example.test" }),
    );

    expect(report.steps.map((step) => [step.name, step.ok])).toEqual([
      ["postgrest", true],
      ["read", true],
    ]);
    expect(fetch.mock.calls.map(([url]) => String(url))).toEqual([
      `${PROJECT_URL}/rest/v1/`,
      "https://read.example.test/rest/v1/",
    ]);
    expect(fetch.mock.calls[0]?.[1]?.headers).toEqual({
      apikey: "sb_publishable_test",
    });
  });

  it("runs select 1 on a pg pool or a postgres sql tag and initializes flags", async () => {
    const query = vi.fn(async () => ({ rows: [] }));
    const unsafe = vi.fn(async () => []);
    const initialize = vi.fn(async () => undefined);

    const pg = await warmUp(deps(), {
      postgres: { query },
      flags: { initialize },
    });

    await warmUp(deps(), { postgres: { unsafe } });

    expect(pg.steps.map((step) => step.name)).toEqual([
      "postgrest",
      "pool",
      "flags",
    ]);
    expect(query).toHaveBeenCalledWith("select 1");
    expect(unsafe).toHaveBeenCalledWith("select 1");
    expect(initialize).toHaveBeenCalledOnce();
  });

  it("reports failures and timeouts instead of throwing", async () => {
    const report = await warmUp(
      deps({
        fetch: async () => new Response("down", { status: 503 }),
        jwks: () => Promise.reject(new Error("no auth server")),
      }),
      {
        postgres: {
          query: () =>
            new Promise(() => {
              // Never settles: the step has to time out.
            }),
        },
        flags: {
          initialize: () => {
            throw new Error("bad flags key");
          },
        },
        timeoutMs: 20,
      },
    );

    expect(
      report.steps.map(({ name, ok, error }) => ({ name, ok, error })),
    ).toEqual([
      { name: "jwks", ok: false, error: "no auth server" },
      { name: "postgrest", ok: false, error: "PostgREST answered 503" },
      { name: "pool", ok: false, error: "timed out after 20 ms" },
      { name: "flags", ok: false, error: "bad flags key" },
    ]);
  });

  it("counts a 4xx from PostgREST as warm: the connection is open", async () => {
    const report = await warmUp(
      deps({ fetch: async () => new Response("", { status: 401 }) }),
    );

    expect(report.steps).toEqual([
      expect.objectContaining({ name: "postgrest", ok: true }),
    ]);
  });
});

describe("server.warm", () => {
  it("loads the remote JWKS through the auth fetch", async () => {
    const authFetch = vi.fn<typeof fetch>(async () =>
      Response.json(signer.jwks),
    );

    const rest = vi.fn<typeof fetch>(async () => new Response("{}"));

    const server = createServer(createSupabase(schema), {
      env: {
        url: PROJECT_URL,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
      },
      prefetchJwks: false,
      fetch: rest,
      auth: { fetch: authFetch },
    });

    const report = await server.warm();

    expect(report.steps.map((step) => [step.name, step.ok])).toEqual([
      ["jwks", true],
      ["postgrest", true],
    ]);
    expect(String(authFetch.mock.calls[0]?.[0])).toContain("jwks.json");
    expect(String(rest.mock.calls[0]?.[0])).toBe(`${PROJECT_URL}/rest/v1/`);
  });

  it("skips the JWKS step when the keys are inline", async () => {
    const server = createServer(createSupabase(schema), {
      env: { url: PROJECT_URL, publishableKey: "sb_publishable_test" },
      fetch: async () => new Response("{}"),
      auth: { jwks: signer.jwks },
    });

    const report = await server.warm();

    expect(report.steps.map((step) => step.name)).toEqual(["postgrest"]);
  });
});
