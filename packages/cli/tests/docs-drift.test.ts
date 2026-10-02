import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { GLOBAL_ARGS } from "../src/command.ts";
import { commandNames, help } from "../src/run.ts";

const docs = join(import.meta.dirname, "../../../apps/docs/content/docs");

/** The page that documents each command's flags. */
const PAGES: Readonly<Record<string, string>> = {
  init: "cli/init.mdx",
  add: "cli/init.mdx",
  env: "cli/local.mdx",
  keys: "cli/local.mdx",
  seed: "cli/local.mdx",
  openapi: "cli/local.mdx",
  gen: "cli/gen.mdx",
  introspect: "cli/introspect.mdx",
  doctor: "cli/doctor.mdx",
  sql: "kits/sql.mdx",
  skills: "for-ai-agents.mdx",
};

const globals = new Set(["help", "version", ...Object.keys(GLOBAL_ARGS)]);

async function flagsOf(command: string): Promise<string[]> {
  const usage = await help(command);
  const flags = [...usage.matchAll(/--([a-z][a-z0-9-]*)/g)].map(
    (match) => match[1] ?? "",
  );
  return [...new Set(flags)].filter((flag) => !globals.has(flag)).toSorted();
}

describe("CLI docs", () => {
  it("has a page for every command", () => {
    expect(commandNames().toSorted()).toEqual(Object.keys(PAGES).toSorted());
  });

  it.each(Object.entries(PAGES))(
    "documents every flag of %s in %s",
    async (command, page) => {
      const text = await readFile(join(docs, page), "utf8");
      const missing = (await flagsOf(command)).filter(
        (flag) => !text.includes(`--${flag}`),
      );
      expect(missing).toEqual([]);
    },
  );

  it("documents the global options and every error code", async () => {
    const index = await readFile(join(docs, "cli/index.mdx"), "utf8");
    for (const flag of Object.keys(GLOBAL_ARGS)) {
      expect(index).toContain(`--${flag}`);
    }
    const errors = await readFile(join(docs, "cli/errors.mdx"), "utf8");
    const headings = [...errors.matchAll(/^## `([a-z_]+)`$/gm)].map(
      (match) => match[1],
    );
    expect(headings).toEqual([
      "usage",
      "unknown_command",
      "missing_value",
      "config_not_found",
      "config_invalid",
      "env_invalid",
      "failed",
      "internal",
    ]);
  });
});
