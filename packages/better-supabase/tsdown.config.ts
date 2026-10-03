import { dirname, relative, resolve } from "node:path";
import { defineConfig } from "tsdown";

const entries = [
  "index",
  "config/index",
  "client/index",
  "react/index",
  "react/server",
  "react/session",
  "query/index",
  "server/index",
  "postgres/index",
  "ssr/index",
  "next/index",
  "next/image/index",
  "hono/index",
  "orpc/index",
  "edge/index",
  "mcp/index",
  "jobs/index",
  "env/index",
  "list/index",
  "storage/index",
  "realtime/index",
  "events/index",
  "webhooks/index",
  "openapi/index",
  "otel/index",
  "plugins/timestamps/index",
  "lint/index",
  "plugins/rules/index",
  "plugins/soft-delete/index",
  "plugins/tenant/index",
  "plugins/actor/index",
  "plugins/validation/index",
  "sql/index",
  "testing/index",
];

const src = resolve(import.meta.dirname, "src");

/**
 * The subpath of a library entry (`src/sql/index.ts` is `sql`), or undefined
 * for any other file. Declaration builds ask for `.d.ts` and `.js` names too.
 */
function librarySubpath(file: string): string | undefined {
  const path = relative(src, file).replace(/(\.d)?\.(ts|js)$/, "");
  if (path === "index") return "";
  if (!path.endsWith("/index") || path.startsWith("cli/")) return undefined;
  const subpath = path.slice(0, -"/index".length);
  return entries.includes(`${subpath}/index`) ? subpath : undefined;
}

const library = defineConfig({
  entry: Object.fromEntries(entries.map((name) => [name, `src/${name}.ts`])),
  platform: "neutral",
  format: "esm",
  dts: true,
  clean: true,
  exports: false,
  plugins: [
    {
      // The declaration bundler drops `/// <reference lib>` directives, and
      // consumers need the Temporal lib wherever the types name it
      // (docs/decisions/0005-temporal.md).
      name: "temporal-lib-reference",
      renderChunk(code, chunk) {
        if (!chunk.fileName.endsWith(".d.ts") || !code.includes("Temporal."))
          return null;
        return `/// <reference lib="esnext.temporal" />\n${code}`;
      },
    },
    {
      // The react-server build imports the provider from the built
      // `react/session.js` entry, so it stays a "use client" reference.
      name: "react-session-reference",
      resolveId(source, importer) {
        if (
          source === "./session.js" &&
          importer?.endsWith("src/react/server.ts")
        )
          return { id: "./session.js", external: true };
        return null;
      },
    },
  ],
  inputOptions: {
    onLog(level, log, handler) {
      // Rolldown keeps "use client" on the react entry chunks; tests/bundle asserts it.
      if (
        log.code === "MODULE_LEVEL_DIRECTIVE" &&
        (log.id?.endsWith("src/react/index.ts") ||
          log.id?.endsWith("src/react/hooks.ts") ||
          log.id?.endsWith("src/react/session.ts"))
      )
        return;
      handler(level, log);
    },
  },
  deps: {
    neverBundle: [
      /^@supabase\//,
      /^@opentelemetry\//,
      /^@orpc\//,
      /^@tanstack\//,
      /^node:/,
      "hono",
      "next",
      /^next\//,
      "pg",
      "react",
      "react-dom",
    ],
  },
});

// The CLI runs on Node and inlines its own packages (citty, c12, valibot and
// the rest are devDependencies), so apps install no CLI dependency
// (invariant 1). It loads the library from the package's own entries, so a
// command and the app's config share one copy of `defineSchema` and the kit.
const cli = defineConfig({
  entry: { "cli/index": "src/cli/index.ts", "cli/bin": "src/cli/bin.ts" },
  platform: "node",
  format: "esm",
  fixedExtension: false,
  dts: true,
  clean: false,
  exports: false,
  outputOptions: { chunkFileNames: "cli/[name]-[hash].js" },
  plugins: [
    {
      name: "library-entries",
      resolveId(source, importer) {
        if (!importer || !source.startsWith(".")) return null;
        const subpath = librarySubpath(resolve(dirname(importer), source));
        if (subpath === undefined) return null;
        return {
          id: subpath === "" ? "better-supabase" : `better-supabase/${subpath}`,
          external: true,
        };
      },
    },
  ],
  deps: {
    neverBundle: [
      /^@supabase\//,
      /^better-supabase(\/|$)/,
      /^node:/,
      "pg",
      // c12's optional peers, each loaded through import() with a fallback.
      "dotenv",
      "giget",
      "jiti",
      "magicast",
    ],
    onlyBundle: [
      "@clack/core",
      "@clack/prompts",
      "@t3-oss/env-core",
      "c12",
      "citty",
      "confbox",
      "defu",
      "destr",
      "diff",
      "exsolve",
      "fast-string-truncated-width",
      "fast-string-width",
      "fast-wrap-ansi",
      "fastest-levenshtein",
      "pathe",
      "pkg-types",
      "rc9",
      "sisteransi",
      "smol-toml",
      "tinyexec",
      "valibot",
    ],
  },
});

export default [library, cli];
