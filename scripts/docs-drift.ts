// Checks the docs against the code: every doctor code has a heading on the
// doctor page, every subpath is in the README table and on a docs page, and
// every `meta.json` lists exactly the pages in its folder. The CLI commands
// and flags are checked by `packages/better-supabase/tests/cli/docs-drift.test.ts`, which
// `pnpm docs:drift` runs after this. Run with `node scripts/docs-drift.ts`.
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

function mdxFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) {
      return mdxFiles(path);
    }
    return name.endsWith(".mdx") ? [path] : [];
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
  const pages = mdxFiles(docs).map((file) => readFileSync(file, "utf8"));
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

const problems = [...doctorCodes(), ...subpaths(), ...metaFiles(docs)];
for (const problem of problems) {
  console.error(`docs drift: ${problem}`);
}
if (problems.length > 0) {
  exit(1);
}
console.log("docs drift: doctor codes, subpaths and meta.json match the code");
