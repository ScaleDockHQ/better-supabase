// Outside tsconfig.json's include, so linting this file alone needs Node's types here.
/// <reference types="node" />
import { dirname, relative, resolve } from "node:path";
import { defineConfig } from "tsdown";

const entries = [
  "index",
  "config/index",
  "preset/index",
  "create/index",
  "create/lite/index",
  "create/oauth/index",
  "create/supabase/index",
  "client/index",
  "client/native/index",
  "react/index",
  "react/server",
  "react/session",
  "react/native/index",
  "query/index",
  "records/index",
  "flows/index",
  "server/index",
  "powersync/react/index",
  "postgres/index",
  "ssr/index",
  "next/index",
  "next/image/index",
  "next/client/index",
  "hono/index",
  "orpc/index",
  "edge/index",
  "expo/index",
  "tanstack-start/index",
  "sveltekit/index",
  "react-router/index",
  "h3/index",
  "elysia/index",
  "node/index",
  "nestjs/index",
  "astro/index",
  "h3/v1/index",
  "nuxt/index",
  "solid-start/index",
  "vue/index",
  "solid/index",
  "svelte/index",
  "mcp/index",
  "mcp/sdk/index",
  "blocks/jobs/index",
  "blocks/index",
  "blocks/audit/index",
  "blocks/outbox/index",
  "blocks/organizations/index",
  "blocks/profiles/index",
  "blocks/notifications/index",
  "blocks/notifications/react/index",
  "blocks/notifications/react/server",
  "blocks/notifications/vue/index",
  "blocks/notifications/svelte/index",
  "blocks/notifications/solid/index",
  "blocks/webhooks/index",
  "blocks/entitlements/index",
  "blocks/entitlements/react/index",
  "blocks/entitlements/react/server",
  "blocks/entitlements/vue/index",
  "blocks/entitlements/svelte/index",
  "blocks/entitlements/solid/index",
  "blocks/access/index",
  "blocks/access/react/index",
  "blocks/access/react/server",
  "blocks/access/vue/index",
  "blocks/access/svelte/index",
  "blocks/access/solid/index",
  "blocks/subjects/index",
  "blocks/subjects/react/index",
  "blocks/subjects/react/server",
  "blocks/subjects/vue/index",
  "blocks/subjects/svelte/index",
  "blocks/subjects/solid/index",
  "blocks/ai-chat/index",
  "blocks/ai-chat/react/index",
  "blocks/ai-chat/react/server",
  "blocks/ai-chat/vue/index",
  "blocks/ai-chat/svelte/index",
  "blocks/ai-chat/solid/index",
  "blocks/ai-files/index",
  "blocks/knowledge/index",
  "blocks/memory/index",
  "blocks/agents/index",
  "blocks/connectors/index",
  "blocks/ai-tasks/index",
  "blocks/ai-cache/index",
  "blocks/ai-providers/index",
  "blocks/number-sequences/index",
  "blocks/teams/index",
  "blocks/undo/index",
  "blocks/undo/react/index",
  "blocks/undo/react/server",
  "blocks/undo/vue/index",
  "blocks/undo/svelte/index",
  "blocks/undo/solid/index",
  "blocks/tags/index",
  "blocks/state-machine/index",
  "blocks/custom-fields/index",
  "blocks/share-links/index",
  "blocks/signing-keys/index",
  "blocks/oauth-server/index",
  "blocks/domains/index",
  "blocks/rules/index",
  "blocks/vercel-marketplace/index",
  "blocks/rules/react/index",
  "blocks/rules/react/server",
  "blocks/rules/vue/index",
  "blocks/rules/svelte/index",
  "blocks/rules/solid/index",
  "blocks/reviews/index",
  "blocks/leave/index",
  "blocks/ledger/index",
  "blocks/assets/index",
  "blocks/shared-signals/index",
  "blocks/identities/index",
  "blocks/service-principals/index",
  "blocks/reminders/index",
  "blocks/imports/index",
  "blocks/rank/index",
  "blocks/saved-views/index",
  "blocks/saved-views/react/index",
  "blocks/saved-views/react/server",
  "blocks/saved-views/vue/index",
  "blocks/saved-views/svelte/index",
  "blocks/saved-views/solid/index",
  "blocks/relations/index",
  "blocks/bulk/index",
  "blocks/search/index",
  "blocks/search/react/index",
  "blocks/search/react/server",
  "blocks/search/vue/index",
  "blocks/search/svelte/index",
  "blocks/search/solid/index",
  "blocks/metrics/index",
  "commerce/index",
  "blocks/calendar/index",
  "blocks/calendar/react/index",
  "blocks/calendar/react/server",
  "blocks/calendar/vue/index",
  "blocks/calendar/svelte/index",
  "blocks/calendar/solid/index",
  "blocks/bookings/index",
  "blocks/bookings/react/index",
  "blocks/bookings/react/server",
  "blocks/bookings/vue/index",
  "blocks/bookings/svelte/index",
  "blocks/bookings/solid/index",
  "blocks/versions/index",
  "blocks/trash/index",
  "blocks/reactions/index",
  "blocks/approvals/index",
  "blocks/access-requests/index",
  "blocks/documents/index",
  "blocks/drive/index",
  "blocks/forms/index",
  "blocks/forms/react/index",
  "blocks/forms/react/server",
  "blocks/forms/vue/index",
  "blocks/forms/svelte/index",
  "blocks/forms/solid/index",
  "blocks/time-tracking/index",
  "blocks/templates/index",
  "blocks/pipelines/index",
  "blocks/parties/index",
  "blocks/collections/index",
  "blocks/engagements/index",
  "blocks/deals/index",
  "blocks/work-items/index",
  "blocks/quotes/index",
  "blocks/invoices/index",
  "blocks/sla/index",
  "blocks/targets/index",
  "blocks/hiring/index",
  "blocks/employees/index",
  "blocks/reactions/react/index",
  "blocks/reactions/react/server",
  "blocks/reactions/vue/index",
  "blocks/reactions/svelte/index",
  "blocks/reactions/solid/index",
  "blocks/comments/react/index",
  "blocks/comments/react/server",
  "blocks/comments/vue/index",
  "blocks/comments/svelte/index",
  "blocks/comments/solid/index",
  "blocks/organizations/react/index",
  "blocks/organizations/react/server",
  "blocks/organizations/vue/index",
  "blocks/organizations/svelte/index",
  "blocks/organizations/solid/index",
  "blocks/audit/react/index",
  "blocks/audit/react/server",
  "blocks/audit/vue/index",
  "blocks/audit/svelte/index",
  "blocks/audit/solid/index",
  "blocks/api-keys/react/index",
  "blocks/api-keys/react/server",
  "blocks/api-keys/vue/index",
  "blocks/api-keys/svelte/index",
  "blocks/api-keys/solid/index",
  "blocks/mfa/react/index",
  "blocks/mfa/react/server",
  "blocks/mfa/vue/index",
  "blocks/mfa/svelte/index",
  "blocks/mfa/solid/index",
  "blocks/sessions/react/index",
  "blocks/sessions/react/server",
  "blocks/sessions/vue/index",
  "blocks/sessions/svelte/index",
  "blocks/sessions/solid/index",
  "blocks/tags/react/index",
  "blocks/tags/react/server",
  "blocks/tags/vue/index",
  "blocks/tags/svelte/index",
  "blocks/tags/solid/index",
  "blocks/catalog/index",
  "blocks/inventory/index",
  "blocks/orders/index",
  "blocks/promotions/index",
  "ai-sdk/index",
  "ai-sdk/chat/index",
  "ai-sdk/files/index",
  "ai-sdk/cache/index",
  "ai-sdk/batches/index",
  "ai-sdk/embeddings/index",
  "ai-sdk/memory/index",
  "ai-sdk/agents/index",
  "ai-sdk/mcp/index",
  "ai-sdk/react/index",
  "ai-sdk/react/server",
  "ai-sdk/workflow/index",
  "ai-sdk/workflow/react/index",
  "ai-sdk/workflow/react/server",
  "blocks/announcements/index",
  "blocks/announcements/react/index",
  "blocks/announcements/react/server",
  "blocks/announcements/vue/index",
  "blocks/announcements/svelte/index",
  "blocks/announcements/solid/index",
  "blocks/waitlist/index",
  "streams/index",
  "streams/redis/index",
  "credentials/index",
  "vercel-connect/index",
  "stripe/index",
  "yjs/index",
  "better-result/index",
  "blocks/inbox/index",
  "blocks/inbox/react/index",
  "blocks/inbox/react/server",
  "blocks/inbox/vue/index",
  "blocks/inbox/svelte/index",
  "blocks/inbox/solid/index",
  "chat-sdk/index",
  "chat-sdk/react/index",
  "chat-sdk/react/server",
  "blocks/onboarding/index",
  "blocks/onboarding/react/index",
  "blocks/onboarding/react/server",
  "blocks/onboarding/vue/index",
  "blocks/onboarding/svelte/index",
  "blocks/onboarding/solid/index",
  "blocks/workflows/index",
  "blocks/workflows/react/index",
  "blocks/workflows/react/server",
  "blocks/workflows/vue/index",
  "blocks/workflows/svelte/index",
  "blocks/workflows/solid/index",
  "blocks/workflow-builder/index",
  "blocks/workflow-builder/react/index",
  "blocks/workflow-builder/react/server",
  "blocks/workflow-builder/vue/index",
  "blocks/workflow-builder/svelte/index",
  "blocks/workflow-builder/solid/index",
  "workflow-sdk/index",
  "workflow-sdk/world/index",
  "eve/index",
  "flags-sdk/index",
  "workflow-sdk/builder/index",
  "blocks/sso/index",
  "blocks/data-lifecycle/index",
  "blocks/attachments/index",
  "blocks/comments/index",
  "blocks/flags/index",
  "blocks/billing/index",
  "blocks/billing/react/index",
  "blocks/billing/react/server",
  "blocks/billing/vue/index",
  "blocks/billing/svelte/index",
  "blocks/billing/solid/index",
  "blocks/usage/index",
  "blocks/usage/react/index",
  "blocks/usage/react/server",
  "blocks/usage/vue/index",
  "blocks/usage/svelte/index",
  "blocks/usage/solid/index",
  "blocks/settings/index",
  "blocks/settings/react/index",
  "blocks/settings/react/server",
  "blocks/settings/vue/index",
  "blocks/settings/svelte/index",
  "blocks/settings/solid/index",
  "blocks/api-keys/index",
  "blocks/mfa/index",
  "blocks/sessions/index",
  "env/index",
  "list/index",
  "storage/index",
  "realtime/index",
  "events/index",
  "openapi/index",
  "spec/index",
  "overlay/index",
  "asyncapi/index",
  "arazzo/index",
  "otel/index",
  "powersync/index",
  "plugins/timestamps/index",
  "lint/index",
  "plugins/rules/index",
  "plugins/soft-delete/index",
  "plugins/tenant/index",
  "plugins/actor/index",
  "plugins/validation/index",
  "sql/index",
  "expo-sqlite/index",
  "tanstack-db/index",
  "tanstack-db/supabase/index",
  "blocks/push/index",
  "testing/index",
];

const src = resolve(import.meta.dirname, "src");

const USE_CLIENT_MODULE =
  /src\/(react\/(index|hooks|session)|blocks\/(notifications|inbox)\/react\/index|chat-sdk\/react\/index)\.ts$/;

/**
 * The subpath of a library entry (`src/sql/index.ts` is `sql`), or undefined
 * for any other file. Declaration builds ask for `.d.ts` and `.js` names too.
 */
function librarySubpath(file: string): string | undefined {
  const path = relative(src, file).replace(/(\.d)?\.(ts|js)$/, "");

  if (path === "index") {
    return "";
  }

  if (!path.endsWith("/index") || path.startsWith("cli/")) {
    return undefined;
  }

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
  // Library modules only declare; the "use client" React modules keep theirs
  // so their directive survives in the entry chunks.
  treeshake: {
    moduleSideEffects: (id) =>
      USE_CLIENT_MODULE.test(id) || !id.startsWith(src),
  },
  plugins: [
    {
      // The declaration bundler drops `/// <reference lib>` directives, and
      // consumers need the Temporal lib wherever the types name it
      // (docs/decisions/0005-temporal.md).
      name: "temporal-lib-reference",
      renderChunk(code, chunk) {
        if (!chunk.fileName.endsWith(".d.ts") || !code.includes("Temporal.")) {
          return null;
        }

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
        ) {
          return { id: "./session.js", external: true };
        }

        return null;
      },
    },
  ],
  inputOptions: {
    onLog(level, log, handler) {
      // Rolldown keeps "use client" on the react entry chunks; tests/bundle asserts it.
      if (
        log.code === "MODULE_LEVEL_DIRECTIVE" &&
        USE_CLIENT_MODULE.test(log.id ?? "")
      ) {
        return;
      }

      handler(level, log);
    },
  },
  deps: {
    neverBundle: [
      /^@supabase\//,
      /^@supabase-labs\//,
      /^@opentelemetry\//,
      /^@orpc\//,
      /^@tanstack\//,
      /^@ai-sdk\//,
      /^@workflow\//,
      /^node:/,
      "ai",
      "hono",
      "next",
      /^next\//,
      "pg",
      "react",
      "react-dom",
      "workflow",
      /^workflow\//,
    ],
  },
});

// The CLI runs on Node and inlines its own packages (citty, c12, valibot and
// the rest are devDependencies), so apps install no CLI dependency
// (invariant 1). It loads the library from the package's own entries, so a
// command and the app's config share one copy of `defineSchema` and the block registry.
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
        if (!importer || !source.startsWith(".")) {
          return null;
        }

        const subpath = librarySubpath(resolve(dirname(importer), source));

        if (subpath === undefined) {
          return null;
        }

        return {
          id: subpath === "" ? "better-supabase" : `better-supabase/${subpath}`,
          external: true,
        };
      },
    },
    {
      // The bin is an executable, not a module anyone imports, so it ships no types.
      name: "no-bin-types",
      generateBundle: {
        order: "post",
        handler(_options, bundle) {
          for (const file of Object.keys(bundle)) {
            if (/^cli\/bin\.d\.[cm]?ts(\.map)?$/.test(file)) {
              delete bundle[file];
            }
          }
        },
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
      "ajv",
      "ajv-formats",
      "c12",
      "citty",
      "confbox",
      "defu",
      "destr",
      "diff",
      "exsolve",
      "fast-deep-equal",
      "fast-string-truncated-width",
      "fast-string-width",
      "fast-uri",
      "fast-wrap-ansi",
      "fastest-levenshtein",
      "json-schema-traverse",
      "jsonpath-rfc9535",
      "pathe",
      "pkg-types",
      "rc9",
      "require-from-string",
      "sisteransi",
      "smol-toml",
      "tinyexec",
      "valibot",
      "yaml",
    ],
  },
});

export default [library, cli];
