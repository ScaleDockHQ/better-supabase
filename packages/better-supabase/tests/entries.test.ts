import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import api from "../api/exports.json" with { type: "json" };
import packageJson from "../package.json" with { type: "json" };

const entryOf = (subpath: string): string =>
  subpath === "." ? "index" : `${subpath.slice(2)}/index`;

/** Barrels whose implementation lives in sibling modules. */
const PURE_BARRELS = [
  "blocks/audit",
  "blocks/entitlements",
  "blocks/ai-chat",
  "blocks/announcements",
  "blocks/waitlist",
  "blocks/onboarding",
  "blocks/profiles",
  "blocks/sso",
  "blocks/data-lifecycle",
  "blocks/attachments",
  "blocks/comments",
  "blocks/flags",
  "blocks/billing",
  "blocks/usage",
  "blocks/settings",
  "blocks/audit",
  "blocks/api-keys",
  "blocks/jobs",
  "blocks/outbox",
  "blocks/webhooks",
  "config",
  "list",
  "mcp",
  "mcp/sdk",
  "next",
  "powersync",
  "query",
  "react",
  "realtime",
  "sql",
  "storage",
  "streams",
  "streams/redis",
  "credentials",
  "vercel-connect",
  "blocks/workflows",
  "workflow-sdk",
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
      "utf8",
    );
    const statements = source
      .replace(/^"use client";$/m, "")
      .replaceAll(/\/\*[\s\S]*?\*\/|^\s*\/\/.*$/gm, "")
      .split(/;\s*\n/)
      .map((statement) => statement.trim())
      .filter(Boolean);
    for (const statement of statements)
      expect(statement).toMatch(
        /^export\s+(type\s+)?(\*|\{[^}]*\})\s+from\s+"[^"]+"$/,
      );
  });
});

describe("the source export condition", () => {
  it("adds only the source path to the published exports", () => {
    const published: Record<string, unknown> =
      packageJson.publishConfig.exports;
    const withoutSource = Object.fromEntries(
      Object.entries(packageJson.exports).map(([key, value]) => {
        if (typeof value === "string") return [key, value];
        const { "@better-supabase/source": _, ...rest } = value;
        return [key, rest];
      }),
    );
    expect(withoutSource).toEqual(published);
  });

  it.each(Object.entries(packageJson.exports))(
    "%s points the source condition at the file its build starts from",
    (_, value) => {
      if (typeof value === "string") return;
      expect(value["@better-supabase/source"]).toBe(
        value.default.replace(/^\.\/dist\//, "./src/").replace(/\.js$/, ".ts"),
      );
    },
  );
});
