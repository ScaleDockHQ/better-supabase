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
  "blocks/queue/index",
  "blocks/index",
  "blocks/audit/index",
  "blocks/outbox/index",
  "blocks/organizations/index",
  "blocks/profiles/index",
  "blocks/notifications/index",
  "blocks/webhooks/index",
  "blocks/entitlements/index",
  "blocks/permissions/index",
  "blocks/subjects/index",
  "blocks/ai-chat/index",
  "blocks/ai-files/index",
  "blocks/knowledge/index",
  "blocks/memory/index",
  "blocks/messaging/index",
  "blocks/channels/index",
  "blocks/agents/index",
  "blocks/connectors/index",
  "blocks/ai-schedules/index",
  "blocks/ai-cache/index",
  "blocks/ai-keys/index",
  "blocks/numbering/index",
  "blocks/teams/index",
  "blocks/undo/index",
  "blocks/tags/index",
  "blocks/state-machine/index",
  "blocks/custom-fields/index",
  "blocks/share-links/index",
  "blocks/signing-keys/index",
  "blocks/oauth-server/index",
  "blocks/domains/index",
  "blocks/automations/index",
  "blocks/vercel-marketplace/index",
  "blocks/reviews/index",
  "blocks/leave/index",
  "blocks/ledger/index",
  "blocks/assets/index",
  "blocks/scores/index",
  "blocks/moderation/index",
  "blocks/enrollments/index",
  "blocks/guests/index",
  "blocks/admission-passes/index",
  "blocks/billable-time/index",
  "blocks/leases/index",
  "blocks/expenses/index",
  "blocks/donations/index",
  "blocks/dispatch/index",
  "blocks/shipments/index",
  "blocks/contracts/index",
  "blocks/compliance/index",
  "blocks/incidents/index",
  "blocks/courses/index",
  "blocks/sequences/index",
  "blocks/lead-scoring/index",
  "blocks/posts/index",
  "blocks/security-events/index",
  "blocks/linked-identities/index",
  "blocks/service-accounts/index",
  "blocks/reminders/index",
  "blocks/imports/index",
  "blocks/rank/index",
  "blocks/saved-views/index",
  "blocks/relations/index",
  "blocks/bulk-actions/index",
  "blocks/search/index",
  "blocks/metrics/index",
  "commerce/index",
  "blocks/calendar/index",
  "blocks/bookings/index",
  "blocks/versions/index",
  "blocks/trash/index",
  "blocks/memberships/index",
  "blocks/created-by/index",
  "blocks/updated-at/index",
  "blocks/reactions/index",
  "blocks/approvals/index",
  "blocks/access-requests/index",
  "blocks/documents/index",
  "blocks/drive/index",
  "blocks/signatures/index",
  "blocks/forms/index",
  "blocks/time-tracking/index",
  "blocks/templates/index",
  "blocks/pipelines/index",
  "blocks/contacts/index",
  "blocks/collections/index",
  "blocks/activities/index",
  "blocks/mail-sync/index",
  "blocks/segments/index",
  "blocks/assignment/index",
  "blocks/enrichment/index",
  "blocks/field-history/index",
  "blocks/forecasts/index",
  "blocks/deals/index",
  "blocks/tasks/index",
  "blocks/quotes/index",
  "blocks/invoices/index",
  "blocks/sla/index",
  "blocks/goals/index",
  "blocks/hiring/index",
  "blocks/employees/index",
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
  "blocks/waitlist/index",
  "streams/index",
  "streams/redis/index",
  "credentials/index",
  "vercel-connect/index",
  "stripe/index",
  "yjs/index",
  "better-result/index",
  "blocks/inbox/index",
  "chat-sdk/index",
  "blocks/onboarding/index",
  "blocks/workflows/index",
  "blocks/workflow-editor/index",
  "workflow-sdk/index",
  "workflow-sdk/world/index",
  "eve/index",
  "flags-sdk/index",
  "workflow-sdk/builder/index",
  "blocks/sso/index",
  "blocks/data-lifecycle/index",
  "blocks/attachments/index",
  "blocks/comments/index",
  "blocks/timeline/index",
  "blocks/feature-flags/index",
  "blocks/billing/index",
  "blocks/usage/index",
  "blocks/settings/index",
  "blocks/api-keys/index",
  "blocks/mfa/index",
  "blocks/session-revocation/index",
  "env/index",
  "list/index",
  "storage/index",
  "realtime/index",
  "events/index",
  "spec/index",
  "otel/index",
  "powersync/index",
  "lint/index",
  "sql/index",
  "expo-sqlite/index",
  "tanstack-db/index",
  "tanstack-db/supabase/index",
  "blocks/push/index",
  "testing/index",
];

const src = resolve(import.meta.dirname, "src");

const USE_CLIENT_MODULE = /src\/react\/(index|hooks|session)\.ts$/;

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
