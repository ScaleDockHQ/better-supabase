import { glob, readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { GLOBAL_ARGS } from "../../src/cli/command.ts";
import { commandNames, help } from "../../src/cli/run.ts";
import {
  INTEGRATIONS,
  type TemplateContext,
  TEMPLATES,
} from "../../src/cli/templates.ts";

const repo = join(import.meta.dirname, "../../../..");
const docs = join(repo, "apps/docs/content/docs");

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
  codemod: "cli/codemod.mdx",
  config: "cli/config.mdx",
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

/** Where the docs, skills, examples and READMEs teach the names. */
const SOURCES = [
  "apps/docs/content/docs",
  "packages/better-supabase/skills",
  "apps/examples",
  "apps/marketing/lib",
  "README.md",
  "packages/better-supabase/README.md",
];
/** Pages that quote the old names on purpose. */
const HISTORY = new Set([
  "apps/docs/content/docs/concepts/naming.mdx",
  "apps/docs/content/docs/migration/0.1-to-0.2.mdx",
]);

async function sources(): Promise<{ path: string; text: string }[]> {
  const paths: string[] = [];
  for await (const path of glob(
    SOURCES.map((source) =>
      /\.\w+$/.test(source) ? source : `${source}/**/*.{md,mdx,ts,tsx}`,
    ),
    {
      cwd: repo,
      exclude: (name) => name === "node_modules" || name === ".next",
    },
  )) {
    if (!/(?:generated|database\.types)\.ts$/.test(path)) paths.push(path);
  }
  const read = paths
    .filter((path) => !HISTORY.has(path))
    .map(async (path) => ({
      path,
      text: await readFile(join(repo, path), "utf8"),
    }));
  return Promise.all(read);
}

const templateContext: TemplateContext = {
  srcDir: "src",
  generated: "src/lib/supabase/generated.ts",
  tsExtensions: false,
  frameworks: ["next"],
  version: "0.0.0",
};

const LEGACY_INSTANCE =
  /\b(?:const|let)\s+(sb|next|browser|server|mcp)\s*=\s*(?:defineSupabase|create[A-Z]\w*)\(/;
const LEGACY_PATH = /supabase\.(?:browser|server|client)(?:\.tsx?)?["'`]/;

describe("naming", () => {
  it("names the definition betterSupabase and every instance bs", async () => {
    const files = [
      ...(await sources()),
      ...INTEGRATIONS.flatMap((name) =>
        TEMPLATES[name].files(templateContext).map((file) => ({
          path: `template ${name}: ${file.path}`,
          text: file.contents,
        })),
      ),
    ];
    const offenders = files.flatMap(({ path, text }) => {
      const found = [LEGACY_INSTANCE, LEGACY_PATH]
        .map((pattern) => pattern.exec(text)?.[0])
        .filter((match) => match !== undefined);
      return found.map((match) => `${path}: ${match}`);
    });
    expect(offenders).toEqual([]);
  });

  it("returns a Better type from every adapter factory", async () => {
    const api: Record<string, { values?: string[]; types?: string[] }> =
      JSON.parse(
        await readFile(
          join(import.meta.dirname, "../../api/exports.json"),
          "utf8",
        ),
      );
    const missing = Object.entries(api).flatMap(([subpath, names]) =>
      (names.values ?? [])
        .filter((name) => FACTORIES.has(name))
        .filter(
          (name) => !names.types?.includes(name.replace(/^create/, "Better")),
        )
        .map((name) => `${subpath}: ${name}`),
    );
    expect(missing).toEqual([]);
    expect(
      Object.values(api)
        .flatMap((names) => names.values ?? [])
        .filter((name) => FACTORIES.has(name)).length,
    ).toBe(FACTORIES.size);
  });
});

/** The factories whose result apps name `bs` (or that the adapters build on). */
const FACTORIES = new Set([
  "createClient",
  "createServer",
  "createNext",
  "createHono",
  "createOrpc",
  "createEdge",
  "createExpo",
  "createMcp",
  "createPostgres",
  "createQueries",
]);
