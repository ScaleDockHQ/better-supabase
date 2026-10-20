import { afterEach, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createEdge } from "../../src/edge/index.ts";
import { ENV_VARIABLES, EnvValidationError } from "../../src/env/index.ts";
import { createHono } from "../../src/hono/index.ts";
import { createMcp } from "../../src/mcp/index.ts";
import { createOrpc } from "../../src/orpc/index.ts";
import { createServer } from "../../src/server/server.ts";
import { schema } from "../fixtures/generated-camel.ts";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("env loading", () => {
  it("waits for the first use, so builds without runtime env can import server modules", () => {
    for (const name of Object.values(ENV_VARIABLES).flat()) {
      vi.stubEnv(name, "");
    }

    const betterSupabase = defineSupabase(schema);

    const servers = [
      createServer(betterSupabase),
      createEdge(betterSupabase),
      createHono(betterSupabase),
      createOrpc(betterSupabase),
      createMcp(betterSupabase, { name: "test", version: "1.0.0" }),
    ];

    for (const server of servers) {
      expect(typeof server.context).toBe("function");
      expect(() => server.env).toThrow(EnvValidationError);
    }
  });

  it("reads an env object only, never the runtime's variables", async () => {
    vi.stubEnv("SUPABASE_URL", "https://leaked.supabase.co");
    vi.stubEnv("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_leaked");
    vi.stubEnv("SUPABASE_JWKS_URL", "https://leaked.test/jwks.json");
    vi.stubEnv("SUPABASE_JWKS", '{"keys":[]}');

    const fetch = vi.fn<typeof globalThis.fetch>(async () =>
      Response.json({ keys: [] }),
    );

    vi.stubGlobal("fetch", fetch);

    const server = createServer(defineSupabase(schema), {
      env: {
        SUPABASE_URL: "http://127.0.0.1:54321",
        SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test",
      },
      auth: { jwks: false },
      prefetchJwks: true,
    });

    expect(server.env.url).toBe("http://127.0.0.1:54321");
    expect(server.env.jwks).toBeUndefined();
    expect(String(server.env.jwksUrl)).toBe(
      "http://127.0.0.1:54321/auth/v1/.well-known/jwks.json",
    );

    const ctx = await server.context(
      new Request("https://app.test/", {
        headers: { authorization: "Bearer a.b.c" },
      }),
    );

    expect(ctx.auth.kind).toBe("invalid");
    expect(fetch).not.toHaveBeenCalled();
    vi.unstubAllGlobals();
  });

  it("fails on a missing variable in the env object instead of using the runtime's", () => {
    vi.stubEnv("SUPABASE_URL", "https://leaked.supabase.co");

    const server = createServer(defineSupabase(schema), {
      env: { SUPABASE_PUBLISHABLE_KEY: "sb_publishable_test" },
    });

    expect(() => server.env).toThrow(EnvValidationError);
  });
});
