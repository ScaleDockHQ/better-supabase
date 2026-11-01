import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import api from "../api/exports.json" with { type: "json" };
import packageJson from "../package.json" with { type: "json" };

const entryOf = (subpath: string): string =>
  subpath === "." ? "index" : `${subpath.slice(2)}/index`;

/** Barrels whose implementation lives in sibling modules. */
const PURE_BARRELS = [
  "blocks",
  "fhir",
  "blocks/audit",
  "blocks/entitlements",
  "blocks/permissions",
  "blocks/subjects",
  "blocks/ai-chat",
  "blocks/ai-files",
  "blocks/knowledge",
  "blocks/memory",
  "blocks/agents",
  "blocks/connectors",
  "blocks/ai-schedules",
  "blocks/push",
  "blocks/ai-cache",
  "blocks/prompts",
  "blocks/ai-keys",
  "ai-sdk",
  "ai-sdk/chat",
  "ai-sdk/files",
  "ai-sdk/cache",
  "ai-sdk/batches",
  "ai-sdk/embeddings",
  "ai-sdk/memory",
  "ai-sdk/agents",
  "ai-sdk/mcp",
  "ai-sdk/workflow",
  "blocks/announcements",
  "blocks/numbering",
  "blocks/teams",
  "blocks/tags",
  "blocks/state-machine",
  "blocks/custom-fields",
  "blocks/share-links",
  "blocks/signing-keys",
  "blocks/oauth-server",
  "blocks/domains",
  "blocks/automations",
  "blocks/vercel-marketplace",
  "blocks/reviews",
  "blocks/leave",
  "blocks/ledger",
  "blocks/assets",
  "blocks/scores",
  "blocks/moderation",
  "blocks/enrollments",
  "blocks/guests",
  "blocks/passes",
  "blocks/billable-time",
  "blocks/leases",
  "blocks/expenses",
  "blocks/donations",
  "blocks/dispatch",
  "blocks/shipments",
  "blocks/contracts",
  "blocks/compliance",
  "blocks/accounting",
  "blocks/acknowledgements",
  "blocks/incidents",
  "blocks/courses",
  "blocks/sequences",
  "blocks/lead-scoring",
  "blocks/posts",
  "blocks/content",
  "blocks/qualifications",
  "blocks/risks",
  "blocks/cases",
  "blocks/inspections",
  "blocks/meetings",
  "blocks/dam",
  "blocks/lims",
  "blocks/rfqs",
  "blocks/tills",
  "blocks/clinical-decision-support",
  "blocks/e-prescribing",
  "blocks/maintenance",
  "blocks/appraisals",
  "blocks/warehouse",
  "blocks/manufacturing",
  "blocks/banking",
  "blocks/tax",
  "blocks/legal-entities",
  "blocks/document-templates",
  "blocks/funding",
  "blocks/payroll-export",
  "blocks/shifts",
  "blocks/consents",
  "blocks/observations",
  "blocks/medications",
  "blocks/care-plans",
  "blocks/security-events",
  "blocks/reminders",
  "blocks/imports",
  "blocks/rank",
  "blocks/saved-views",
  "blocks/service-accounts",
  "blocks/relations",
  "blocks/bulk",
  "blocks/undo",
  "blocks/search",
  "blocks/metrics",
  "commerce",
  "blocks/calendar",
  "blocks/bookings",
  "blocks/versions",
  "blocks/trash",
  "blocks/reactions",
  "blocks/approvals",
  "blocks/access-requests",
  "blocks/documents",
  "blocks/catalog",
  "blocks/inventory",
  "blocks/drive",
  "blocks/orders",
  "blocks/promotions",
  "blocks/forms",
  "blocks/time-tracking",
  "blocks/templates",
  "blocks/pipelines",
  "blocks/contacts",
  "blocks/collections",
  "blocks/activities",
  "blocks/deals",
  "blocks/tasks",
  "blocks/quotes",
  "blocks/invoices",
  "blocks/sla",
  "blocks/goals",
  "blocks/hiring",
  "blocks/employees",
  "blocks/waitlist",
  "blocks/onboarding",
  "blocks/profiles",
  "blocks/sso",
  "blocks/data-lifecycle",
  "blocks/attachments",
  "blocks/comments",
  "blocks/timeline",
  "blocks/flags",
  "blocks/billing",
  "blocks/usage",
  "blocks/settings",
  "blocks/audit",
  "blocks/api-keys",
  "blocks/queue",
  "blocks/outbox",
  "blocks/webhooks",
  "config",
  "list",
  "mcp",
  "mcp/sdk",
  "next",
  "powersync",
  "tanstack-db",
  "sqlite",
  "query",
  "react",
  "realtime",
  "rate-limit",
  "sql",
  "storage",
  "streams",
  "streams/redis",
  "credentials",
  "vercel-connect",
  "vercel-sandbox",
  "stripe",
  "yjs",
  "better-result",
  "blocks/workflows",
  "workflow-sdk",
  "blocks/workflow-editor",
  "workflow-sdk/builder",
  "blocks/inbox",
  "blocks/messaging",
  "blocks/channels",
  "blocks/mail-sync",
  "blocks/segments",
  "blocks/assignment",
  "blocks/enrichment",
  "blocks/field-history",
  "blocks/forecasts",
  "chat-sdk",
  "eve",
  "flags-sdk",
  "e-invoicing",
  "audit-files",
];

describe("subpath entries", () => {
  it.each(Object.keys(api))(
    "%s defines every runtime export",
    { timeout: 30_000 },
    async (subpath) => {
      const file = new URL(`../src/${entryOf(subpath)}.ts`, import.meta.url);
      const module = (await import(file.href)) as Record<string, unknown>;

      const { values } = (api as Record<string, { values: string[] }>)[
        subpath
      ]!;

      expect(values.filter((name) => module[name] === undefined)).toEqual([]);
    },
  );

  it.each(PURE_BARRELS)("%s/index.ts only re-exports", async (entry) => {
    const source = await readFile(
      new URL(`../src/${entry}/index.ts`, import.meta.url),
      "utf-8",
    );

    const statements = source
      .replace(/^"use client";$/m, "")
      .replaceAll(/\/\*[\s\S]*?\*\/|^\s*\/\/.*$/gm, "")
      .split(/;\s*\n/)
      .map((statement) => statement.trim())
      .filter(Boolean);

    for (const statement of statements) {
      expect(statement).toMatch(
        /^export\s+(type\s+)?(\*|\{[^}]*\})\s+from\s+"[^"]+"$/,
      );
    }
  });
});

describe("the source export condition", () => {
  it("adds only the source path to the published exports", () => {
    const published: Record<string, unknown> =
      packageJson.publishConfig.exports;

    const withoutSource = Object.fromEntries(
      Object.entries(packageJson.exports).map(([key, value]) => {
        if (typeof value === "string") {
          return [key, value];
        }

        const { "@better-supabase/source": _, ...rest } = value;

        return [key, rest];
      }),
    );

    expect(withoutSource).toEqual(published);
  });

  it.each(Object.entries(packageJson.exports))(
    "%s points the source condition at the file its build starts from",
    (_, value) => {
      if (typeof value === "string") {
        return;
      }

      expect(value["@better-supabase/source"]).toBe(
        value.default.replace(/^\.\/dist\//, "./src/").replace(/\.js$/, ".ts"),
      );
    },
  );
});
