// Checks the docs against the code: every doctor code has a heading on the
// doctor page, every subpath is in the README table and on a docs page, and
// every `meta.json` lists exactly the pages in its folder, and every titled
// `lib/supabase/*` code block in the docs and skills follows the Naming page.
// The CLI commands
// and flags are checked by `packages/better-supabase/tests/cli/docs-drift.test.ts`, which
// runs with the package's unit tests. Run with `node scripts/docs-drift.ts`.
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { cwd, exit } from "node:process";
import * as v from "valibot";

const root = cwd();
const docs = join(root, "apps/docs/content/docs");
const library = join(root, "packages/better-supabase");

const DoctorReport = v.object({
  properties: v.object({
    findings: v.object({
      items: v.object({
        properties: v.object({
          code: v.object({ enum: v.array(v.string()) }),
        }),
      }),
    }),
  }),
});
const PackageExports = v.object({ exports: v.record(v.string(), v.unknown()) });
const Meta = v.object({ pages: v.optional(v.array(v.string()), []) });

function readJson<const Schema extends v.GenericSchema>(
  schema: Schema,
  path: string,
): v.InferOutput<Schema> {
  return v.parse(schema, JSON.parse(readFileSync(path, "utf8")));
}

function doctorCodes(): string[] {
  const codes = readJson(
    DoctorReport,
    join(library, "schemas/doctor-report-v1.json"),
  ).properties.findings.items.properties.code.enum;
  const page = readFileSync(join(docs, "cli/doctor.mdx"), "utf8");
  const headings = new Set(
    [...page.matchAll(/^### (BS\d{3})$/gmu)].map((match) => match[1]),
  );
  return [
    ...codes
      .filter((code) => !headings.has(code))
      .map((code) => `cli/doctor.mdx has no "### ${code}" heading`),
    ...[...headings]
      .filter((code) => code !== undefined && !codes.includes(code))
      .map(
        (code) =>
          `cli/doctor.mdx documents ${code ?? ""}, which the report schema does not list`,
      ),
  ];
}

function markdownFiles(dir: string, extension: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      return markdownFiles(path, extension);
    }
    return name.endsWith(extension) ? [path] : [];
  });
}

/**
 * The imports in the first column of the README subpath table. A cell may
 * group entries: `` `/edge` `` is relative to the cell's first import, and
 * `plugins/*` covers every plugin.
 */
function readmeImports(readme: string): string[] {
  return readme.split("\n").flatMap((line) => {
    const cell = /^\| (`better-supabase[^|]*)\|/u.exec(line)?.[1] ?? "";
    const names = [...cell.matchAll(/`([^`]+)`/gu)].map(
      (match) => match[1] ?? "",
    );
    return names.map((name) =>
      name.startsWith("/") ? `better-supabase${name}` : name,
    );
  });
}

function inTable(entry: string, imports: readonly string[]): boolean {
  return imports.some((name) =>
    name.endsWith("/*") ? entry.startsWith(name.slice(0, -1)) : name === entry,
  );
}

function subpaths(): string[] {
  const { exports: exportsMap } = readJson(
    PackageExports,
    join(library, "package.json"),
  );
  const imports = readmeImports(
    readFileSync(join(library, "README.md"), "utf8"),
  );
  const pages = markdownFiles(docs, ".mdx").map((file) =>
    readFileSync(file, "utf8"),
  );
  const entries = Object.keys(exportsMap)
    .filter((key) => !key.includes("*") && key !== "./package.json")
    .map((key) =>
      key === "." ? "better-supabase" : `better-supabase/${key.slice(2)}`,
    );
  return entries.flatMap((entry) => {
    const quoted = `"${entry}"`;
    const problems: string[] = [];
    if (!inTable(entry, imports)) {
      problems.push(`${entry} is missing from the README subpath table`);
    }
    if (!pages.some((page) => page.includes(quoted))) {
      problems.push(`no docs page imports from ${quoted}`);
    }
    return problems;
  });
}

function isPageEntry(entry: string): boolean {
  return !(
    entry.startsWith("---") ||
    entry.startsWith("...") ||
    entry.startsWith("!") ||
    entry.startsWith("[")
  );
}

function metaFiles(dir: string): string[] {
  const problems: string[] = [];
  const names = readdirSync(dir);
  const children = names.flatMap((name) => {
    if (statSync(join(dir, name)).isDirectory()) {
      problems.push(...metaFiles(join(dir, name)));
      return [name];
    }
    return name.endsWith(".mdx") ? [name.slice(0, -".mdx".length)] : [];
  });
  const where = relative(docs, dir) || ".";
  const metaPath = join(dir, "meta.json");
  if (!existsSync(metaPath)) {
    return [...problems, `${where} has no meta.json`];
  }
  const listed = readJson(Meta, metaPath).pages.filter(isPageEntry);
  if (listed.length === 0) {
    return [...problems, `${where}/meta.json has no explicit pages order`];
  }
  return [
    ...problems,
    ...listed
      .filter((entry) => !children.includes(entry))
      .map(
        (entry) => `${where}/meta.json lists "${entry}", which does not exist`,
      ),
    ...children
      .filter((child) => !listed.includes(child))
      .map((child) => `${where}/meta.json does not list "${child}"`),
  ];
}

interface CodeBlock {
  readonly title: string;
  readonly body: string;
  readonly line: number;
}

/** Fenced code blocks with a `title="..."`, also when a list indents them. */
function titledBlocks(text: string): CodeBlock[] {
  const lines = text.split("\n");
  const blocks: CodeBlock[] = [];
  for (let index = 0; index < lines.length; index += 1) {
    const open = /^(\s*)```\w*.*\btitle="([^"]+)"/u.exec(lines[index] ?? "");
    if (!open) {
      continue;
    }
    const indent = open[1] ?? "";
    const body: string[] = [];
    let end = index + 1;
    while (end < lines.length && lines[end]?.trim() !== "```") {
      body.push((lines[end] ?? "").slice(indent.length));
      end += 1;
    }
    blocks.push({
      title: open[2] ?? "",
      body: body.join("\n"),
      line: index + 1,
    });
    index = end;
  }
  return blocks;
}

/**
 * The Naming page's file layout: the definition from `defineSupabase` lives
 * in `lib/supabase/index.ts`, never in the `server.ts` or `client.ts` that
 * create `bs`, and a Next.js `server.ts` starts with `import "server-only"`.
 */
function naming(): string[] {
  const files = [
    ...markdownFiles(docs, ".mdx"),
    ...markdownFiles(join(library, "skills"), ".md"),
  ];
  return files.flatMap((file) =>
    titledBlocks(readFileSync(file, "utf8")).flatMap((block) => {
      const where = `${relative(root, file)}:${String(block.line)}`;
      const problems: string[] = [];
      if (
        /lib\/supabase\/(?:server|client)\.ts$/u.test(block.title) &&
        block.body.includes("defineSupabase(")
      ) {
        problems.push(
          `${where} defines betterSupabase in ${block.title}; it belongs in src/lib/supabase/index.ts (concepts/naming.mdx)`,
        );
      }
      if (
        block.title.endsWith("lib/supabase/server.ts") &&
        block.body.includes("createNext(") &&
        !block.body.trimStart().startsWith('import "server-only";')
      ) {
        problems.push(
          `${where} creates bs with createNext in ${block.title} without starting with import "server-only" (concepts/naming.mdx)`,
        );
      }
      return problems;
    }),
  );
}

const problems = [
  ...doctorCodes(),
  ...subpaths(),
  ...metaFiles(docs),
  ...naming(),
];
for (const problem of problems) {
  console.error(`docs drift: ${problem}`);
}
if (problems.length > 0) {
  exit(1);
}
console.log(
  "docs drift: doctor codes, subpaths, meta.json and lib/supabase naming match the code",
);
