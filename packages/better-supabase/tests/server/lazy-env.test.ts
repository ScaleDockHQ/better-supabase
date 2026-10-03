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
    for (const name of Object.values(ENV_VARIABLES).flat())
      vi.stubEnv(name, "");
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
});
