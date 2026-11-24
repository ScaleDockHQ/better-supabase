// Lists every generated module of the Next.js example with the app files that
// import it, and fails when more modules are unused than the committed
// baseline allows, so the count only goes down. `--write` rewrites the
// baseline and the report. Run with `node scripts/check-example-generated.ts`.
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { argv, exit } from "node:process";

const APP = "apps/examples/nextjs";
const GENERATED = `${APP}/src/lib/supabase`;
const BASELINE = `${APP}/perf/generated-coverage.json`;
const REPORT = "docs/agents/example-generated.md";
const SOURCES = [`${APP}/src`, `${APP}/tests`, `${APP}/coverage`];

const files = (dir: string): string[] =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);

    if (name === "node_modules" || name === ".next") {
      return [];
    }

    return statSync(path).isDirectory() ? files(path) : [path];
  });

const isCode = (path: string): boolean => /\.(?:ts|tsx|js)$/u.test(path);

export interface Row {
  readonly module: string;
  readonly users: readonly string[];
}

export const stem = (path: string): string =>
  relative(GENERATED, path)
    .split(sep)
    .join("/")
    .replace(/\.d\.ts$|\.(?:ts|tsx|js)$/u, "");

export const importsOf = (source: string, module: string): boolean => {
  const base = module.split("/").pop() ?? module;
  const escaped = base.replaceAll(".", String.raw`\.`);

  return new RegExp(
    String.raw`from\s+["'][^"']*supabase/(?:[^"']*/)?${escaped}(?:\.[jt]s)?["']`,
    "u",
  ).test(source);
};

export const buildRows = (): Row[] => {
  const modules = [...new Set(files(GENERATED).filter(isCode).map(stem))];

  const users = SOURCES.flatMap((dir) => files(dir))
    .filter((path) => isCode(path) && !path.startsWith(`${GENERATED}/`))
    .map((path) => ({ path, source: readFileSync(path, "utf-8") }));

  return modules
    .toSorted()
    .map((module) => ({
      module,
      users: users
        .filter(({ source }) => importsOf(source, module))
        .map(({ path }) => relative(APP, path)),
    }));
};

export const markdown = (rows: readonly Row[]): string => {
  const unused = rows.filter((row) => row.users.length === 0);

  return [
    "# Example generated coverage",
    "",
    "Written by `node scripts/check-example-generated.ts --write`; do not edit by hand.",
    "",
    `${rows.length} generated modules, ${rows.length - unused.length} imported by app code or tests, ${unused.length} not.`,
    "",
    "| Module | Importers |",
    "| --- | --- |",
    ...rows.map((row) => `| ${row.module} | ${row.users.length} |`),
    "",
  ].join("\n");
};

if (argv[1]?.endsWith("check-example-generated.ts")) {
  const rows = buildRows();
  const unused = rows.filter((row) => row.users.length === 0).length;

  if (argv.includes("--write")) {
    writeFileSync(BASELINE, `${JSON.stringify({ unused }, null, 2)}\n`);
    writeFileSync(REPORT, markdown(rows));
    console.log(`Wrote ${rows.length} modules, ${unused} unused.`);
  } else {
    // SAFETY: `--write` is the only writer of this file and stores `{ unused }`.
    const baseline = JSON.parse(readFileSync(BASELINE, "utf-8")) as {
      unused: number;
    };

    const allowed = baseline.unused;

    console.log(
      `Example generated modules: ${rows.length - unused} of ${rows.length} used, ${unused} not (baseline ${allowed}).`,
    );

    if (unused > allowed) {
      console.error("More generated modules are unused than the baseline.");
      exit(1);
    }
  }
}
