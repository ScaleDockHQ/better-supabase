import { glob, readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { TemplateContext } from "../../src/cli/templates.ts";

import { GLOBAL_ARGS } from "../../src/cli/core/command.ts";
import { CLI_ERROR_CODES } from "../../src/cli/core/errors.ts";
import { effectsLine } from "../../src/cli/core/help.ts";
import { findSpec, specPaths } from "../../src/cli/core/manifest.ts";
import { commandNames, help } from "../../src/cli/core/run.ts";
import { INTEGRATIONS, TEMPLATES } from "../../src/cli/templates.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

const repo = join(import.meta.dirname, "../../../..");
const docs = join(repo, "apps/docs/content/docs");

/** The page that documents each command's flags. */
const PAGES: Readonly<Record<string, string>> = {
  init: "cli/init.mdx",
  add: "cli/init.mdx",
  remove: "cli/init.mdx",
  upgrade: "cli/init.mdx",
  blocks: "cli/presets.mdx",
  dev: "cli/dev.mdx",
  db: "cli/db.mdx",
  spec: "cli/spec.mdx",
  scaffold: "cli/scaffold.mdx",
  gen: "cli/gen.mdx",
  mcp: "cli/mcp.mdx",
  doctor: "cli/doctor.mdx",
  skills: "for-ai-agents.mdx",
  codemod: "cli/codemod.mdx",
  completion: "cli/completion.mdx",
  config: "cli/config.mdx",
};

/**
 * Each global option as help prints it: `--no-color` for a boolean that is on
 * by default.
 */
const globalFlags = Object.entries(GLOBAL_ARGS).map(([name, definition]) =>
  definition.type === "boolean" && "default" in definition
    ? `no-${name}`
    : name,
);

const globals = new Set(["help", "version", ...globalFlags]);

/** The flags of `command` and of every subcommand under it. */
async function flagsOf(command: string): Promise<string[]> {
  const paths = specPaths().filter((path) => path[0] === command);
  const usages = await Promise.all(paths.map((path) => help(path.join(" "))));

  const flags = usages.flatMap((usage) =>
    [...usage.matchAll(/--([a-z][a-z0-9-]*)/g)].map((match) => match[1] ?? ""),
  );

  return [...new Set(flags)].filter((flag) => !globals.has(flag)).toSorted();
}

/** The commands each page documents. */
function pagesByFile(): Record<string, string[]> {
  const pages: Record<string, string[]> = {};

  for (const [command, page] of Object.entries(PAGES)) {
    (pages[page] ??= []).push(command);
  }

  return pages;
}

const slug = (heading: string): string =>
  heading
    .toLowerCase()
    .replaceAll(/[^a-z0-9 -]/g, "")
    .trim()
    .replaceAll(" ", "-");

/**
 * The text under the heading whose anchor is `anchor`, up to the next heading
 * at its level or above.
 */
function section(text: string, anchor: string): string {
  const lines = text.split("\n");

  const start = lines.findIndex((line) => {
    const heading = /^(#{2,6}) (.+)$/.exec(line);

    return heading?.[2] !== undefined && slug(heading[2]) === anchor;
  });

  if (start === -1) {
    return "";
  }

  const level = /^#+/.exec(lines[start] ?? "")?.[0].length ?? 2;

  const end = lines.findIndex(
    (line, at) =>
      at > start && (/^#+ /.exec(line)?.[0].length ?? 99) - 1 <= level,
  );

  return lines.slice(start, end === -1 ? undefined : end).join("\n");
}

/** Whether another leaf command links the same docs section. */
function sharesSection(command: string): boolean {
  const docs = findSpec(command.split(" "))?.docs;

  return (
    specPaths().filter(
      (path) => !findSpec(path)?.subcommands && findSpec(path)?.docs === docs,
    ).length > 1
  );
}

describe("CLI docs", () => {
  it("has a page for every command", () => {
    expect(commandNames().toSorted()).toEqual(Object.keys(PAGES).toSorted());
  });

  it.each(Object.entries(PAGES))(
    "documents every flag of %s in %s",
    async (command, page) => {
      const text = await readFile(join(docs, page), "utf-8");

      const missing = (await flagsOf(command)).filter(
        (flag) => !text.includes(`--${flag}`),
      );

      expect(missing).toEqual([]);
    },
  );

  it.each(Object.entries(pagesByFile()))(
    "has no flag rows in %s that the commands lack",
    async (page, commands) => {
      const text = await readFile(join(docs, page), "utf-8");

      const known = new Set(
        (await Promise.all(commands.map(flagsOf)))
          .flat()
          .flatMap((flag) => [flag, flag.replace(/^no-/, "")]),
      );

      const rows = [...text.matchAll(/^\| `--([a-z][a-z0-9-]*)/gm)].map(
        (match) => match[1] ?? "",
      );

      expect(
        rows.filter((flag) => !known.has(flag) && !globals.has(flag)),
      ).toEqual([]);
    },
  );

  it.each(
    specPaths()
      .filter((path) => !findSpec(path)?.subcommands)
      .map((path) => path.join(" ")),
  )("gives %s a Side effects line in its docs section", async (command) => {
    const spec = findSpec(command.split(" "));
    const [page = "", anchor] = (spec?.docs ?? "").split("#");

    const text = await readFile(
      join(docs, `${page.replace(/^\/docs\//, "")}.mdx`),
      "utf-8",
    );

    const area = anchor ? section(text, anchor) : text;
    const line = effectsLine(spec?.effects ?? []);
    const lines = area.replaceAll("`", "").split("\n");

    expect(area).not.toBe("");
    expect(
      lines.some(
        (each) =>
          each === `Side effects of ${command}: ${line}` ||
          each.replaceAll(/ +/g, " ") === `| ${command} | ${line} |` ||
          (!sharesSection(command) && each.startsWith(`Side effects: ${line}`)),
      ),
    ).toBe(true);
  });

  it("documents the global options and every error code", async () => {
    const index = await readFile(join(docs, "cli/index.mdx"), "utf-8");

    for (const flag of globalFlags) {
      expect(index).toContain(`--${flag}`);
    }

    const errors = await readFile(join(docs, "cli/errors.mdx"), "utf-8");

    const headings = [...errors.matchAll(/^## `([a-z_]+)`$/gm)].map(
      (match) => match[1],
    );

    expect(headings).toEqual(CLI_ERROR_CODES);
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
    if (!/(?:generated|database\.types)\.ts$/.test(path)) {
      paths.push(path);
    }
  }

  const read = paths
    .filter((path) => !HISTORY.has(path))
    .map(async (path) => ({
      path,
      text: await readFile(join(repo, path), "utf-8"),
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
  it("names the definition betterSupabase and every instance bsb", async () => {
    const files = [
      ...(await sources()),
      ...INTEGRATIONS.flatMap((name) =>
        TEMPLATES[name]
          .files(templateContext)
          .map((file) => ({
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
          "utf-8",
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
        .filter((name) => FACTORIES.has(name)),
    ).toHaveLength(FACTORIES.size);
  });
});

/** The factories whose result apps name `bsb` (or that the adapters build on). */
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

describe("blocks overview", () => {
  it("lists every module with what it requires and works with", async () => {
    const page = await readFile(join(docs, "blocks/index.mdx"), "utf-8");
    const section = page.slice(page.indexOf("## How modules work together"));

    const cell = (names: readonly string[]): string =>
      names.length === 0
        ? "none"
        : names
            .map((name) =>
              name === "*" ? "every installed module" : `\`${name}\``,
            )
            .join(", ");

    const rows = [
      ...section.matchAll(/^\| `([a-z-]+)` +\| (.+?) +\| (.+?) +\|$/gm),
    ].map(([, name, requires, works]) => `${name} | ${requires} | ${works}`);

    const expected = Object.values(SQL_MODULES).map((module) => {
      const required = new Set(module.requires);

      const works = [
        ...new Set([
          ...(module.integrates ?? []),
          ...Object.keys(module.contributes ?? {}),
        ]),
      ].filter((name) => !required.has(name));

      return `${module.name} | ${cell(module.requires)} | ${cell(works)}`;
    });

    expect(rows).toEqual(expected);
  });
});
