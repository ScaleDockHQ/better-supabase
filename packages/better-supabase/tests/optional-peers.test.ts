import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const manifest: {
  devDependencies: Record<string, string>;
  peerDependencies: Record<string, string>;
  peerDependenciesMeta: Record<string, { optional?: boolean }>;
} = JSON.parse(
  await readFile(join(import.meta.dirname, "../package.json"), "utf-8"),
);

/**
 * SDKs better-supabase integrates with but never imports at the top of a
 * runtime entry: it types them structurally or loads them on first use. Each
 * stays an optional peer, so a release outside the tested range warns the app,
 * and a devDependency, so the conformance tests run against its real types.
 */
const INTEGRATIONS = [
  "@ai-sdk/anthropic",
  "@openfeature/server-sdk",
  "@powersync/common",
  "@supabase-labs/middleware-openfeature",
  "@supabase/pg-delta",
  "@supabase/pg-topo",
  "@vercel/connect",
  "@vercel/queue",
  "flags",
  "stripe",
  "yjs",
  "redis",
  "jsonpath-rfc9535",
  "temporal-polyfill",
] as const;

/**
 * Frameworks the adapters type structurally. Each is an optional peer with a
 * tested range: `tests/frameworks.test-d.ts` checks the current major, and
 * `tests/types/frameworks-previous` the previous one where the range keeps it.
 */
const FRAMEWORKS = [
  "@solidjs/start",
  "@sveltejs/kit",
  "@tanstack/react-start",
  "astro",
  "elysia",
  "express",
  "fastify",
  "h3",
  "koa",
  "nuxt",
  "react-router",
] as const;

/**
 * Libraries only generated code imports (`nuqs()` writes `nuqs/server`). The
 * app installs them; the tests import the generated fixtures.
 */
const GENERATED = ["nuqs"] as const;

/**
 * SDKs one subpath imports at its top (`better-supabase/chat-sdk` imports
 * `chat`). Only apps that import that subpath install them.
 */
const SUBPATH_SDKS = ["ai", "chat", "workflow"] as const;

describe("optional peers", () => {
  it.each([...INTEGRATIONS, ...FRAMEWORKS, ...GENERATED, ...SUBPATH_SDKS])(
    "%s is an optional peer and a devDependency",
    (name) => {
      expect(manifest.peerDependencies[name]).toBe("catalog:peers");
      expect(manifest.peerDependenciesMeta[name]?.optional).toBe(true);
      expect(manifest.devDependencies[name]).toBeDefined();
    },
  );

  it("only @supabase/supabase-js is a required peer", () => {
    expect(
      Object.keys(manifest.peerDependencies).filter(
        (name) => manifest.peerDependenciesMeta[name]?.optional !== true,
      ),
    ).toEqual(["@supabase/supabase-js"]);
  });
});
