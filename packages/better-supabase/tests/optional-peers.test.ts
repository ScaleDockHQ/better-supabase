import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const manifest: {
  dependencies: Record<string, string>;
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
  "@ai-sdk/harness",
  "@ai-sdk/sandbox-vercel",
  "@chat-adapter/catalog",
  "@chat-adapter/whatsapp",
  "@json-render/core",
  "@openfeature/server-sdk",
  "@powersync/common",
  "@supabase-labs/middleware-openfeature",
  "@vercel/blob",
  "@vercel/connect",
  "@vercel/firewall",
  "@vercel/functions",
  "@vercel/kms",
  "@vercel/passport",
  "@vercel/queue",
  "@vercel/sandbox",
  "@vercel/schedules",
  "@vercel/sdk",
  "@workflow/world",
  "@workflow/world-postgres",
  "botid",
  "eve",
  "flags",
  "mammoth",
  "stripe",
  "unpdf",
  "yjs",
  "fast-xml-parser",
  "redis",
  "resumable-stream",
  "jsonpath-rfc9535",
  "temporal-polyfill",
  "typescript",
  "undici",
] as const;

/**
 * Frameworks the adapters type structurally. Each is an optional peer with a
 * tested range of one major (two for h3, whose 1.x is the `h3/v1` entry), and
 * `tests/frameworks.test-d.ts` checks it.
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
 * Libraries only generated code imports (`nuqs()` writes `nuqs/server`, `zod()`
 * writes `zod`, `valibot()` writes `valibot`). The app installs them; the tests
 * import the generated fixtures.
 */
const GENERATED = ["nuqs", "valibot", "zod"] as const;

/**
 * SDKs one subpath imports at its top (`better-supabase/chat-sdk` imports
 * `chat`). Only apps that import that subpath install them.
 */
const SUBPATH_SDKS = ["ai", "chat", "workflow"] as const;

describe("dependencies", () => {
  it("are the allow list, so a new one needs an ADR", () => {
    expect(Object.keys(manifest.dependencies).toSorted()).toEqual(
      [
        "@standard-schema/spec",
        "@supabase/middleware",
        "@supabase/pg-delta",
        "@supabase/pg-parser",
        "@supabase/pg-topo",
        "@supabase/postgrest-js",
        "@supabase/server",
        "@supabase/ssr",
        "oxc-parser",
      ].toSorted(),
    );
  });

  it("are no peers, so an app never installs a second copy", () => {
    for (const name of Object.keys(manifest.dependencies)) {
      expect(manifest.peerDependencies[name]).toBeUndefined();
    }
  });
});

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
