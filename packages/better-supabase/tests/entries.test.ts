import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import api from "../api/exports.json" with { type: "json" };

const entryOf = (subpath: string): string =>
  subpath === "." ? "index" : `${subpath.slice(2)}/index`;

/** Barrels whose implementation lives in sibling modules. */
const PURE_BARRELS = [
  "config",
  "jobs",
  "list",
  "mcp",
  "next",
  "query",
  "react",
  "realtime",
  "sql",
  "storage",
  "webhooks",
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
      .split(/;\s*\n/)
      .map((statement) => statement.trim())
      .filter(Boolean);
    for (const statement of statements)
      expect(statement).toMatch(
        /^export\s+(type\s+)?(\*|\{[^}]*\})\s+from\s+"[^"]+"$/,
      );
  });
});
