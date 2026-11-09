import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { ok } from "../../src/core/result.ts";
import { createEdge } from "../../src/edge/index.ts";
import { betterSupabase, env, signer } from "../fixtures/test-server.ts";

const SRC = join(import.meta.dirname, "../../src");

/** The framework adapters (ADR 0094): the first-party entries over a server. */
const ADAPTERS = [
  "astro/index.ts",
  "edge/index.ts",
  "expo/index.ts",
  "hono/index.ts",
  "mcp/mcp.ts",
  "next/create.ts",
  "orpc/index.ts",
  "react-router/create.ts",
  "solid-start/index.ts",
  "sveltekit/create.ts",
  "tanstack-start/create.ts",
] as const;

describe("adapterBase conformance", () => {
  it.each(ADAPTERS)(
    "%s takes its expose default from adapterBase",
    async (file) => {
      const text = await readFile(join(SRC, file), "utf-8");

      expect(text).toContain('from "../server/adapter-base.ts"');
      expect(text).not.toMatch(/\bdefaultExpose\(/);
    },
  );

  it("lists every adapter that imports adapterBase", async () => {
    const found: string[] = [];

    for (const entry of await readdir(SRC, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.name === "server") {
        continue;
      }

      for (const file of await readdir(join(SRC, entry.name))) {
        if (!file.endsWith(".ts")) {
          continue;
        }

        const text = await readFile(join(SRC, entry.name, file), "utf-8");

        if (text.includes('from "../server/adapter-base.ts"')) {
          found.push(`${entry.name}/${file}`);
        }
      }
    }

    expect(found.toSorted()).toStrictEqual([...ADAPTERS].toSorted());
  });
});

const guest = (): Request => new Request("https://app.test/api/notes");

/**
 * An unsigned request through each adapter that refuses a caller itself (the
 * others leave the decision to the route).
 */
const refusals = {
  edge: (exposeErrors: boolean): Promise<Response> => {
    const bsb = createEdge(betterSupabase, {
      env,
      auth: { jwks: signer.jwks },
      prefetchJwks: false,
      exposeErrors,
    });

    return bsb.handler(() => ok("reached"))(guest());
  },
} satisfies Record<string, (exposeErrors: boolean) => Promise<Response>>;

describe.each(Object.entries(refusals))("%s refusals", (_name, refuse) => {
  it("answers a caller with no credentials with Problem Details", async () => {
    const response = await refuse(true);

    expect(response.status).toBe(401);
    expect(response.headers.get("content-type")).toContain("problem+json");
    expect(await response.json()).toMatchObject({
      instance: "/api/notes",
      status: 401,
    });
  });

  it("answers the same Problem Details whichever the exposeErrors option", async () => {
    const hidden = await (await refuse(false)).json();
    const shown = await (await refuse(true)).json();

    expect(hidden).toStrictEqual(shown);
  });
});
