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
  "@vercel/connect",
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

describe("optional peers", () => {
  it.each([...INTEGRATIONS, ...FRAMEWORKS])(
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
